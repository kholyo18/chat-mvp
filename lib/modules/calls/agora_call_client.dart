import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isJoined = false;
  bool _isJoining = false;
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

  bool get isInitialized => _isInitialized;
  bool get isJoined => _isJoined;
  String? get currentChannelId => _currentChannelId;
  int? get localUid => _localUid;

  RtcEngine get engine => _requireEngine();

  RtcEngine? get maybeEngine => _engine;

  Future<void> init() => initializeIfNeeded();

  RtcEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw AgoraCallException('Agora engine is not initialized');
    }
    return engine;
  }

  void _validateAppId() {
    final appId = AgoraConfig.appId.trim();
    if (appId.isEmpty || appId == 'YOUR_AGORA_APP_ID') {
      throw AgoraCallException(
        'إعدادات الاتصال غير مكتملة. يرجى التحقق من App ID الخاص بخدمة Agora.',
      );
    }
  }

  Future<void> initializeIfNeeded() async {
    if (_isInitialized) {
      return;
    }
    _validateAppId();
    debugPrint(
      'AgoraCallClient: Initializing engine (appIdConfigured=${AgoraConfig.appId.trim().isNotEmpty})',
    );
    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(
      RtcEngineContext(
        appId: AgoraConfig.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint(
            'AgoraCallClient: Joined channel ${connection.channelId} as uid=${connection.localUid} in ${elapsed}ms',
          );
          _isJoined = true;
          isLocalUserJoined.value = true;
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          debugPrint('AgoraCallClient: Left channel ${connection.channelId}');
          _isJoined = false;
          isLocalUserJoined.value = false;
          remoteUserIds.value = <int>{};
          _currentChannelId = null;
          _isVideoCall = false;
          isMuted.value = false;
          isSpeakerEnabled.value = false;
          _localUid = null;
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint('AgoraCallClient: Remote user $remoteUid joined channel ${connection.channelId} in ${elapsed}ms');
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
            (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          debugPrint('AgoraCallClient: Remote user $remoteUid left channel ${connection.channelId} (${reason.name})');
          final next = <int>{...remoteUserIds.value}..remove(remoteUid);
          remoteUserIds.value = next;
          _remoteUserEventsController.add(
            AgoraRemoteUserEvent(
              uid: remoteUid,
              type: AgoraRemoteUserEventType.left,
            ),
          );
        },
        onConnectionStateChanged: (
          RtcConnection connection,
          ConnectionStateType state,
          ConnectionChangedReasonType reason,
        ) {
          debugPrint(
            'AgoraCallClient: Connection state changed to ${state.name} due to ${reason.name} (channel=${connection.channelId})',
          );
        },
        onConnectionLost: (RtcConnection connection) {
          debugPrint('AgoraCallClient: Connection lost for ${connection.channelId}');
        },
        onError: (ErrorCodeType error, String message) {
          debugPrint(
            'AgoraCallClient: Engine error ${error.name}(${error.value()}) => $message',
          );
        },
      ),
    );
    _isInitialized = true;
    debugPrint('AgoraCallClient: Engine initialized');
  }

  Future<void> joinVoiceChannel({
    required String channelId,
  }) async {
    await _joinChannel(
      channelId: channelId,
      isVideo: false,
    );
  }

  Future<void> joinVideoChannel({
    required String channelId,
  }) async {
    await _joinChannel(
      channelId: channelId,
      isVideo: true,
    );
  }

  @visibleForTesting
  Future<void> startCall({
    required String channelId,
    required bool isVideo,
  }) async {
    await _joinChannel(channelId: channelId, isVideo: isVideo);
  }

  Future<void> _joinChannel({
    required String channelId,
    required bool isVideo,
  }) async {
    await _ensurePermissions(isVideo: isVideo);
    await initializeIfNeeded();
    final engine = _requireEngine();

    if (_isJoining) {
      if (_currentChannelId == channelId) {
        debugPrint('AgoraCallClient: Join already in progress for $channelId');
        return;
      }
      await leaveCall();
    }

    if (_isJoined) {
      if (_currentChannelId == channelId) {
        debugPrint('AgoraCallClient: Already joined $channelId');
        return;
      }
      await leaveCall();
    }

    _isJoining = true;

    _isVideoCall = isVideo;
    _currentChannelId = channelId;
    final uid = _resolveLocalUid();
    isMuted.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};

    await engine.enableAudio();
    await engine.muteLocalAudioStream(false);

    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    if (isVideo) {
      await engine.enableVideo();
      await engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: const VideoDimensions(width: 960, height: 540),
          frameRate: FrameRate.frameRateFps30.value(),
          orientationMode: OrientationMode.orientationModeAdaptive,
        ),
      );
      await engine.startPreview();
      await engine.setEnableSpeakerphone(true);
      isSpeakerEnabled.value = true;
    } else {
      await engine.stopPreview();
      await engine.disableVideo();
      await engine.setEnableSpeakerphone(false);
      isSpeakerEnabled.value = false;
    }

    try {
      final configuredToken = AgoraConfig.token?.trim();
      final hasToken = configuredToken != null && configuredToken.isNotEmpty;
      final tokenToUse = hasToken ? configuredToken! : '';
      debugPrint(
        'AgoraCallClient: Joining channel $channelId (video=$isVideo, uid=$uid, tokenProvided=$hasToken)',
      );
      await engine.joinChannel(
        token: tokenToUse,
        channelId: channelId,
        uid: uid,
        options: ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideo,
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
        ),
      );
      if (!hasToken) {
        debugPrint('AgoraCallClient: Joined channel $channelId without token (App ID mode)');
      }
    } on AgoraRtcException catch (error) {
      _currentChannelId = null;
      _isJoined = false;
      _localUid = null;
      debugPrint('AgoraCallClient: joinChannel failed $error');
      final errorCode = _errorCodeTypeFromValue(error.code);
      throw AgoraCallException(
        _localizedMessageForError(
          errorCode,
          rawCode: error.code,
        ),
        error,
      );
    } catch (error) {
      _currentChannelId = null;
      _isJoined = false;
      _localUid = null;
      debugPrint('AgoraCallClient: joinChannel threw $error');
      throw AgoraCallException(
        'تعذر الاتصال بالمكالمة. حاول مرة أخرى.',
        error,
      );
    } finally {
      _isJoining = false;
    }
  }

  Future<void> leaveCall() async {
    if (!_isInitialized) {
      return;
    }
    debugPrint('AgoraCallClient: Leaving current call (channel=$_currentChannelId)');
    final engine = _requireEngine();
    if (_isJoined) {
      try {
        await engine.leaveChannel();
      } catch (error) {
        debugPrint('AgoraCallClient: leaveChannel error $error');
        rethrow;
      }
    }
    if (_isVideoCall) {
      await engine.stopPreview();
    }
    await engine.disableVideo();
    _isJoined = false;
    _currentChannelId = null;
    _isVideoCall = false;
    _isJoining = false;
    isMuted.value = false;
    isSpeakerEnabled.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};
    _localUid = null;
  }

  Future<void> dispose() async {
    if (_engine == null) {
      return;
    }
    try {
      await leaveCall();
    } finally {
      try {
        await _engine?.release();
      } catch (error) {
        debugPrint('AgoraCallClient: Failed to release engine $error');
      }
      _engine = null;
      _isInitialized = false;
    }
  }

  String _localizedMessageForError(ErrorCodeType code, {int? rawCode}) {
    final intCode = rawCode ?? code.value();
    const networkErrorCodes = <int>{104, 1114, 1115};
    if (networkErrorCodes.contains(intCode)) {
      return 'لا يوجد اتصال بالشبكة. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }
    switch (intCode) {
      case 101:
        return 'معرّف تطبيق Agora غير صالح. يرجى التحقق من الإعدادات.';
      case 102:
        return 'قناة المكالمة غير صالحة. حاول مرة أخرى بعد لحظات.';
      case 109:
        return 'بيانات المصادقة للمكالمة غير صحيحة. يرجى إعادة المحاولة.';
      case 17:
        return 'تم رفض الاتصال بالمكالمة. يرجى المحاولة مجددًا.';
      default:
        return 'تعذر الاتصال بالمكالمة. رمز الخطأ: $intCode';
    }
  }

  ErrorCodeType _errorCodeTypeFromValue(int code) {
    try {
      return ErrorCodeTypeExt.fromValue(code);
    } catch (_) {
      return ErrorCodeType.errFailed;
    }
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
      throw AgoraCallException('Video is not enabled');
    }
    final engine = _requireEngine();
    await engine.switchCamera();
  }

  Future<void> toggleVideoEnabled() async {
    final engine = _requireEngine();
    _isVideoCall = !_isVideoCall;
    if (_isVideoCall) {
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

  int _resolveLocalUid() {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw AgoraCallException(
        'يجب تسجيل الدخول لإجراء المكالمة.',
      );
    }
    final uid = _stableAgoraUid(firebaseUser.uid);
    _localUid = uid;
    return uid;
  }

  int agoraUidForUser(String userId) => _stableAgoraUid(userId);

  int _stableAgoraUid(String uid) {
    final bytes = utf8.encode(uid);
    var hash = 0;
    for (final byte in bytes) {
      hash = (hash * 31 + byte) & 0x7fffffff;
    }
    if (hash == 0) {
      return 1;
    }
    return hash;
  }
}
