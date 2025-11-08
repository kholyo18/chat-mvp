import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/agora_config.dart';

/// Base class for Agora related errors surfaced to the UI layer.
class AgoraCallException implements Exception {
  AgoraCallException(
    this.message, {
    this.cause,
    this.agoraErrorCode,
  });

  final String message;
  final Object? cause;
  final int? agoraErrorCode;

  @override
  String toString() =>
      'AgoraCallException(message: $message, code: $agoraErrorCode, cause: $cause)';
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

/// Singleton responsible for configuring and interacting with the Agora SDK.
class AgoraCallClient {
  AgoraCallClient._();

  factory AgoraCallClient() => instance;

  static final AgoraCallClient instance = AgoraCallClient._();

  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isReleased = false;
  bool _isJoined = false;
  bool _isJoining = false;
  bool _isVideoCall = false;
  bool _videoCapabilityEnabled = false;
  String? _currentChannelId;
  int? _localUid;
  int? _lastJoinResultCode;
  int? _lastEngineErrorCode;
  Future<void>? _initializationFuture;
  Future<void>? _joinFuture;
  Future<void>? _leaveFuture;
  String? _joiningChannelId;

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
  int? get lastJoinResultCode => _lastJoinResultCode;
  int? get lastEngineErrorCode => _lastEngineErrorCode;

  RtcEngine get engine => _requireEngine();

  RtcEngine? get maybeEngine => _engine;

  /// Ensures that the Agora engine exists and is configured for the requested
  /// media capabilities.
  Future<void> initEngineIfNeeded({required bool enableVideo}) async {
    if (_engine != null && _isInitialized && !_isReleased) {
      await _ensureVideoCapability(enableVideo: enableVideo);
      return;
    }
    if (_initializationFuture != null) {
      await _initializationFuture;
      await _ensureVideoCapability(enableVideo: enableVideo);
      return;
    }
    final future = _createAndInitializeEngine(enableVideo: enableVideo);
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  /// Joins the provided Agora [channelId].
  Future<void> joinChannel({
    required String channelId,
    String? token,
    required int uid,
    required bool withVideo,
  }) async {
    final trimmedChannel = channelId.trim();
    if (trimmedChannel.isEmpty) {
      throw AgoraCallException('معرّف قناة الاتصال غير صالح.');
    }

    await _ensurePermissions(isVideo: withVideo);
    await initEngineIfNeeded(enableVideo: withVideo);

    final engine = _requireEngine();

    if (_joinFuture != null) {
      if (_joiningChannelId == trimmedChannel) {
        _log('Join already in progress for $trimmedChannel, awaiting existing operation.');
        await _joinFuture;
        return;
      }
      try {
        await _joinFuture;
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    }

    if (_isJoined && _currentChannelId == trimmedChannel) {
      _log('Already joined channel $trimmedChannel');
      return;
    }

    if (_isJoined && _currentChannelId != trimmedChannel) {
      await leaveChannel();
    }

    _lastJoinResultCode = null;
    _lastEngineErrorCode = null;
    _isJoining = true;
    _isVideoCall = withVideo;
    _currentChannelId = trimmedChannel;
    _localUid = uid;
    _joiningChannelId = trimmedChannel;

    isMuted.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};

    await _prepareMediaForJoin(engine, withVideo: withVideo);

    final effectiveToken = _resolveEffectiveToken(token);
    _log(
      'Joining Agora channel: id=$trimmedChannel uid=$uid video=$withVideo '
      'tokenProvided=${effectiveToken != null}',
    );

    final joinOperation = engine.joinChannel(
      token: effectiveToken ?? '',
      channelId: trimmedChannel,
      uid: uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        publishCameraTrack: withVideo,
        autoSubscribeAudio: true,
        autoSubscribeVideo: withVideo,
      ),
    );
    _joinFuture = joinOperation;

    try {
      await joinOperation;
      _lastJoinResultCode = 0;
      _log('joinChannel completed for $trimmedChannel');
    } on AgoraRtcException catch (error) {
      await _handleJoinFailureCleanup(engine, withVideo: withVideo);
      _lastJoinResultCode = error.code;
      _log(
        'joinChannel failed: code=${error.code} message=${error.message ?? 'unknown'}',
      );
      _resetAfterJoinFailure();
      throw AgoraCallException(
        _localizedMessageForError(
          _errorCodeTypeFromValue(error.code),
          rawCode: error.code,
        ),
        cause: error,
        agoraErrorCode: error.code,
      );
    } catch (error) {
      await _handleJoinFailureCleanup(engine, withVideo: withVideo);
      _log('joinChannel failed with unexpected error: $error');
      _resetAfterJoinFailure();
      throw AgoraCallException(
        'تعذر الاتصال بالمكالمة. حاول مرة أخرى.',
        cause: error,
      );
    } finally {
      if (identical(_joinFuture, joinOperation)) {
        _joinFuture = null;
      }
      _joiningChannelId = null;
      _isJoining = false;
    }
  }

  /// Leaves the currently joined Agora channel, if any.
  Future<void> leaveChannel() async {
    final engine = _engine;
    if (engine == null) {
      _log('leaveChannel skipped: engine is null');
      return;
    }
    if (_leaveFuture != null) {
      _log('leaveChannel already in progress, awaiting existing operation.');
      await _leaveFuture;
      return;
    }
    if (_joinFuture != null) {
      _log('Awaiting ongoing join before leaving.');
      try {
        await _joinFuture;
      } catch (_) {
        // Ignore join errors when leaving.
      }
    }

    final leaveFuture = _performLeave(engine);
    _leaveFuture = leaveFuture;
    try {
      await leaveFuture;
    } finally {
      if (identical(_leaveFuture, leaveFuture)) {
        _leaveFuture = null;
      }
    }
  }

  Future<void> dispose() async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    _log('Releasing Agora engine.');
    try {
      await leaveChannel();
    } catch (error, stack) {
      _log('Error while leaving channel during dispose: $error');
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
    try {
      await engine.release();
    } catch (error) {
      _log('Failed to release Agora engine: $error');
    }
    _engine = null;
    _isInitialized = false;
    _isReleased = true;
    _initializationFuture = null;
    _joinFuture = null;
    _leaveFuture = null;
    _joiningChannelId = null;
    _resetState();
  }

  Future<void> toggleMute() async {
    final engine = _requireEngine();
    final next = !isMuted.value;
    isMuted.value = next;
    await engine.muteLocalAudioStream(next);
    _log('Local audio ${next ? 'muted' : 'unmuted'}');
  }

  Future<void> toggleSpeakerphone() async {
    final engine = _requireEngine();
    final next = !isSpeakerEnabled.value;
    isSpeakerEnabled.value = next;
    await engine.setEnableSpeakerphone(next);
    _log('Speakerphone ${next ? 'enabled' : 'disabled'}');
  }

  Future<void> switchCamera() async {
    if (!_isVideoCall) {
      throw AgoraCallException('Video is not enabled');
    }
    final engine = _requireEngine();
    await engine.switchCamera();
    _log('Camera switched');
  }

  Future<void> toggleVideoEnabled() async {
    final engine = _requireEngine();
    _isVideoCall = !_isVideoCall;
    if (_isVideoCall) {
      await engine.enableVideo();
      await engine.startPreview();
      await engine.setEnableSpeakerphone(true);
      isSpeakerEnabled.value = true;
      _videoCapabilityEnabled = true;
    } else {
      await engine.stopPreview();
      await engine.disableVideo();
      await engine.setEnableSpeakerphone(false);
      isSpeakerEnabled.value = false;
      _videoCapabilityEnabled = false;
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

  int agoraUidForUser(String userId) => _stableAgoraUid(userId);

  // region internal helpers

  void _log(String message) {
    debugPrint('[Agora] $message');
  }

  RtcEngine _requireEngine() {
    final engine = _engine;
    if (engine == null || _isReleased) {
      throw AgoraCallException('Agora engine is not initialized');
    }
    return engine;
  }

  Future<void> _ensureVideoCapability({required bool enableVideo}) async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    if (enableVideo && !_videoCapabilityEnabled) {
      await engine.enableVideo();
      _videoCapabilityEnabled = true;
      _log('Video capability enabled for upcoming call.');
    } else if (!enableVideo && _videoCapabilityEnabled && !_isVideoCall) {
      await engine.disableVideo();
      _videoCapabilityEnabled = false;
      _log('Video capability disabled (audio call).');
    }
  }

  Future<void> _prepareMediaForJoin(
    RtcEngine engine, {
    required bool withVideo,
  }) async {
    await engine.enableAudio();
    await engine.muteLocalAudioStream(false);
    if (withVideo) {
      if (!_videoCapabilityEnabled) {
        await engine.enableVideo();
        _videoCapabilityEnabled = true;
      }
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
      if (_videoCapabilityEnabled) {
        await engine.disableVideo();
        _videoCapabilityEnabled = false;
      }
      await engine.stopPreview();
      await engine.setEnableSpeakerphone(false);
      isSpeakerEnabled.value = false;
    }
  }

  Future<void> _handleJoinFailureCleanup(
    RtcEngine engine, {
    required bool withVideo,
  }) async {
    if (withVideo) {
      await engine.stopPreview().catchError((_) {});
      await engine.disableVideo().catchError((_) {});
      await engine.setEnableSpeakerphone(false).catchError((_) {});
      isSpeakerEnabled.value = false;
      _videoCapabilityEnabled = false;
    }
  }

  void _resetState() {
    _isJoined = false;
    _isJoining = false;
    _isVideoCall = false;
    _currentChannelId = null;
    _localUid = null;
    _lastJoinResultCode = null;
    _lastEngineErrorCode = null;
    _videoCapabilityEnabled = false;
    isMuted.value = false;
    isSpeakerEnabled.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};
  }

  void _resetAfterJoinFailure() {
    _isJoined = false;
    _isJoining = false;
    _isVideoCall = false;
    _currentChannelId = null;
    _localUid = null;
    isLocalUserJoined.value = false;
    isMuted.value = false;
    isSpeakerEnabled.value = false;
    _videoCapabilityEnabled = false;
    remoteUserIds.value = <int>{};
  }

  Future<void> _performLeave(RtcEngine engine) async {
    if (!_isJoined && !_isJoining) {
      _log('leaveChannel called but client was not joined.');
      _resetState();
      return;
    }
    _log('Leaving Agora channel $_currentChannelId');
    try {
      await engine.leaveChannel();
      _log('leaveChannel completed for $_currentChannelId');
    } on AgoraRtcException catch (error) {
      _lastEngineErrorCode = error.code;
      _log(
        'leaveChannel AgoraRtcException code=${error.code} message=${error.message}',
      );
      throw AgoraCallException(
        'تعذر مغادرة المكالمة، حاول مرة أخرى.',
        cause: error,
        agoraErrorCode: error.code,
      );
    } catch (error) {
      _log('leaveChannel unexpected error: $error');
      throw AgoraCallException(
        'تعذر مغادرة المكالمة، حاول مرة أخرى.',
        cause: error,
      );
    } finally {
      if (_isVideoCall) {
        await engine.stopPreview().catchError((_) {});
      }
      await engine.disableVideo().catchError((_) {});
      _resetState();
    }
  }

  Future<void> _createAndInitializeEngine({required bool enableVideo}) async {
    _log('Initializing Agora engine (enableVideo=$enableVideo)...');
    final String appId;
    try {
      appId = AgoraConfig.ensureValidAppId();
    } on FlutterError catch (error) {
      _log('Agora configuration invalid: ${error.message}');
      throw AgoraCallException(
        'إعدادات مكالمات Agora غير متاحة حالياً. يرجى المحاولة لاحقًا.',
        cause: error,
      );
    }

    final engine = createAgoraRtcEngine();
    try {
      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
      await engine.enableAudio();
      if (enableVideo) {
        await engine.enableVideo();
        _videoCapabilityEnabled = true;
      } else {
        await engine.disableVideo();
        _videoCapabilityEnabled = false;
      }
      engine.registerEventHandler(_createEventHandler());
      _engine = engine;
      _isInitialized = true;
      _isReleased = false;
      _log('Agora engine initialized successfully.');
    } on AgoraRtcException catch (error) {
      _log('Agora initialization failed code=${error.code} message=${error.message}');
      await engine.release().catchError((_) {});
      throw AgoraCallException(
        'تعذّر تهيئة مكالمات Agora. حاول مرة أخرى لاحقًا.',
        cause: error,
        agoraErrorCode: error.code,
      );
    } catch (error) {
      _log('Unexpected error while initializing Agora: $error');
      await engine.release().catchError((_) {});
      throw AgoraCallException(
        'تعذّر تهيئة مكالمات Agora. حاول مرة أخرى لاحقًا.',
        cause: error,
      );
    }
  }

  RtcEngineEventHandler _createEventHandler() {
    return RtcEngineEventHandler(
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
        _log(
          'onJoinChannelSuccess: channel=${connection.channelId} uid=${connection.localUid} elapsed=$elapsed',
        );
        _isJoined = true;
        _isJoining = false;
        _currentChannelId = connection.channelId;
        _localUid = connection.localUid;
        isLocalUserJoined.value = true;
      },
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        _log('onLeaveChannel: channel=${connection.channelId}');
        _resetState();
      },
      onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
        _log(
          'onUserJoined: channel=${connection.channelId} uid=$remoteUid elapsed=$elapsed',
        );
        final next = <int>{...remoteUserIds.value, remoteUid};
        remoteUserIds.value = next;
        _remoteUserEventsController.add(
          AgoraRemoteUserEvent(
            uid: remoteUid,
            type: AgoraRemoteUserEventType.joined,
          ),
        );
      },
      onUserOffline: (
        RtcConnection connection,
        int remoteUid,
        UserOfflineReasonType reason,
      ) {
        _log(
          'onUserOffline: channel=${connection.channelId} uid=$remoteUid reason=${reason.name}',
        );
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
        final code = error.value();
        _lastEngineErrorCode = code;
        _log('Agora error code=$code type=${error.name} message=$message');
      },
      onConnectionStateChanged: (
        RtcConnection connection,
        ConnectionStateType state,
        ConnectionChangedReasonType reason,
      ) {
        _log(
          'Connection state changed: ${state.name} (reason=${reason.name}, channel=${connection.channelId})',
        );
      },
      onConnectionLost: (RtcConnection connection) {
        _log('Connection lost for channel ${connection.channelId}');
      },
    );
  }

  String? _resolveEffectiveToken(String? token) {
    final override = AgoraConfig.normalizedToken(token);
    if (override != null) {
      return override;
    }
    return AgoraConfig.normalizedToken();
  }

  String _localizedMessageForError(ErrorCodeType code, {int? rawCode}) {
    final intCode = rawCode ?? code.value();
    const networkErrorCodes = <int>{104, 1114, 1115};
    if (networkErrorCodes.contains(intCode)) {
      return 'لا يوجد اتصال بالشبكة. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }
    switch (intCode) {
      case 3:
        return 'مشكلة في إعدادات مكالمات Agora (App ID / Token). يرجى المحاولة لاحقًا.';
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

  // endregion
}
