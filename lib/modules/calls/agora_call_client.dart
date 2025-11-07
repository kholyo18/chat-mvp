import 'dart:async';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/agora_config.dart';

/// Base class for Agora related errors surfaced to the UI layer.
class AgoraCallException implements Exception {
  AgoraCallException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'AgoraCallException(message: $message, cause: $cause)';
}

/// Thrown when one or more required runtime permissions are missing.
class AgoraPermissionException extends AgoraCallException {
  AgoraPermissionException(this.missingPermissions)
      : super('Missing permissions: ${missingPermissions.join(', ')}');

  final List<Permission> missingPermissions;
}

/// Event describing a remote participant joining or leaving the RTC channel.
class AgoraRemoteUserEvent {
  AgoraRemoteUserEvent({
    required this.uid,
    required this.type,
  });

  final int uid;
  final AgoraRemoteUserEventType type;
}

enum AgoraRemoteUserEventType { joined, left }

/// Thin wrapper around [RtcEngine] to manage the DM call lifecycle.
class AgoraCallClient {
  AgoraCallClient._internal();

  factory AgoraCallClient() => instance;

  static final AgoraCallClient instance = AgoraCallClient._internal();

  late final RtcEngine _engine;
  bool _initialized = false;
  bool _isVideoCall = false;
  String? _currentChannelId;
  int? _localUid;

  final ValueNotifier<bool> isMuted = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isSpeakerEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLocalUserJoined = ValueNotifier<bool>(false);
  final ValueNotifier<Set<int>> remoteUserIds =
      ValueNotifier<Set<int>>(<int>{});

  final StreamController<AgoraRemoteUserEvent> _remoteUserEventsController =
      StreamController<AgoraRemoteUserEvent>.broadcast();

  Stream<AgoraRemoteUserEvent> get remoteUserEvents =>
      _remoteUserEventsController.stream;

  bool get isInitialized => _initialized;
  String? get currentChannelId => _currentChannelId;

  bool get isConnected => _currentChannelId != null;

  Future<void> initialize({required String appId}) async {
    if (_initialized) {
      return;
    }
    _engine = createAgoraRtcEngine();
    await _engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          isLocalUserJoined.value = true;
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          isLocalUserJoined.value = false;
          remoteUserIds.value = <int>{};
          _currentChannelId = null;
          _localUid = null;
          _isVideoCall = false;
          isSpeakerEnabled.value = false;
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          final next = <int>{...remoteUserIds.value, remoteUid};
          remoteUserIds.value = next;
          _remoteUserEventsController.add(
            AgoraRemoteUserEvent(
              uid: remoteUid,
              type: AgoraRemoteUserEventType.joined,
            ),
          );
        },
        onUserOffline:
            (RtcConnection connection, int remoteUid, UserOfflineReasonType _) {
          final next = <int>{...remoteUserIds.value}..remove(remoteUid);
          remoteUserIds.value = next;
          _remoteUserEventsController.add(
            AgoraRemoteUserEvent(
              uid: remoteUid,
              type: AgoraRemoteUserEventType.left,
            ),
          );
        },
        onError: (ErrorCodeType error, String message) {
          debugPrint('Agora engine error $error => $message');
        },
      ),
    );
    _initialized = true;
  }

  RtcEngine get engine => _requireEngine();

  RtcEngine? get maybeEngine => _initialized ? _engine : null;

  RtcEngine _requireEngine() {
    if (!_initialized) {
      throw AgoraCallException('Engine is not initialized');
    }
    return _engine;
  }

  Future<void> startVoiceCall({
    required String channelName,
    required String userId,
  }) async {
    await _startCall(
      channelName: channelName,
      userId: userId,
      isVideo: false,
    );
  }

  Future<void> startVideoCall({
    required String channelName,
    required String userId,
  }) async {
    await _startCall(
      channelName: channelName,
      userId: userId,
      isVideo: true,
    );
  }

  Future<void> toggleMute() async {
    final engine = _requireEngine();
    final next = !isMuted.value;
    isMuted.value = next;
    await engine.muteLocalAudioStream(next);
  }

  Future<void> toggleSpeakerphone() async {
    final engine = _requireEngine();
    final next = !isSpeakerEnabled.value;
    isSpeakerEnabled.value = next;
    await engine.setEnableSpeakerphone(next);
  }

  Future<void> switchCamera() async {
    if (!_isVideoCall) {
      return;
    }
    final engine = _requireEngine();
    await engine.switchCamera();
  }

  Future<void> endCall() async {
    if (!_initialized) {
      return;
    }
    try {
      final engine = _requireEngine();
      await engine.leaveChannel();
      if (_isVideoCall) {
        await engine.stopPreview();
        await engine.disableVideo();
      }
    } finally {
      _currentChannelId = null;
      _localUid = null;
      _isVideoCall = false;
      isMuted.value = false;
      isSpeakerEnabled.value = false;
      isLocalUserJoined.value = false;
      remoteUserIds.value = <int>{};
    }
  }

  Future<void> _startCall({
    required String channelName,
    required String userId,
    required bool isVideo,
  }) async {
    await _ensurePermissions(isVideo: isVideo);
    await initialize(appId: AgoraConfig.appId);
    final engine = _requireEngine();
    _isVideoCall = isVideo;
    isMuted.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};

    if (_currentChannelId != null) {
      await engine.leaveChannel();
      await engine.stopPreview();
    }

    await engine.enableAudio();
    await engine.muteLocalAudioStream(false);

    if (isVideo) {
      await engine.enableVideo();
      await engine.startPreview();
      await engine.setEnableSpeakerphone(true);
      isSpeakerEnabled.value = true;
    } else {
      await engine.stopPreview();
      await engine.disableVideo();
      await engine.setEnableSpeakerphone(false);
      isSpeakerEnabled.value = false;
    }

    final uid = _uidFromString(userId);
    _localUid = uid;
    _currentChannelId = channelName;

    final options = ChannelMediaOptions(
      channelProfile: ChannelProfileType.channelProfileCommunication,
      clientRoleType: ClientRoleType.clientRoleBroadcaster,
      publishMicrophoneTrack: true,
      publishCameraTrack: isVideo,
      autoSubscribeAudio: true,
      autoSubscribeVideo: isVideo,
    );

    final token = AgoraConfig.token;
    await engine.joinChannel(
      token: token ?? '',
      channelId: channelName,
      uid: uid,
      options: options,
    );
  }

  Future<void> _ensurePermissions({required bool isVideo}) async {
    if (kIsWeb) {
      return;
    }
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return;
    }
    final permissions = <Permission>[Permission.microphone];
    if (isVideo) {
      permissions.add(Permission.camera);
    }
    final missing = <Permission>[];
    for (final permission in permissions) {
      final status = await permission.status;
      if (status.isGranted) {
        continue;
      }
      final result = await permission.request();
      if (!result.isGranted) {
        missing.add(permission);
      }
    }
    if (missing.isNotEmpty) {
      throw AgoraPermissionException(missing);
    }
  }

  int _uidFromString(String uid) {
    // Convert the Firebase auth uid to a stable positive integer under 2^31.
    final hash = uid.hashCode & 0x7fffffff;
    return hash % 0x7fffffff;
  }
}
