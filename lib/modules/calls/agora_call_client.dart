import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

/// Thin wrapper around [RtcEngine] to manage the DM call lifecycle.
class AgoraCallClient {
  AgoraCallClient._();

  factory AgoraCallClient() => instance;

  static final AgoraCallClient instance = AgoraCallClient._();

  RtcEngine? _engine;
  bool _isInitialized = false;
  bool _isEngineReleased = false;
  bool _isJoined = false;
  bool _isJoining = false;
  bool _isVideoCall = false;
  bool _isDisposing = false;
  String? _currentChannelId;
  int? _localUid;
  int? _lastJoinResultCode;
  int? _lastEngineErrorCode;
  Future<void>? _initializationFuture;
  Future<void>? _ongoingJoin;
  Future<void>? _disposeFuture;
  String? _joiningChannelId;
  bool _hasLoggedAppId = false;

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

  Future<void> initEngineIfNeeded({required bool enableVideo}) =>
      _ensureEngineInitialized(enableVideo: enableVideo);

  void _log(String message) {
    debugPrint('[AGORA] $message');
  }

  RtcEngine _requireEngine() {
    if (_isDisposing) {
      throw AgoraCallException('Agora engine is shutting down.');
    }
    final engine = _engine;
    if (engine == null) {
      throw AgoraCallException('Agora engine is not initialized');
    }
    return engine;
  }

  String _obtainAppId() {
    try {
      final value = AgoraConfig.appId;
      if (!_hasLoggedAppId) {
        _hasLoggedAppId = true;
        _log('Using Agora App ID ${_maskAppId(value)}');
      }
      return value;
    } on FlutterError catch (error) {
      _log('Agora App ID validation failed: ${error.message}');
      throw AgoraCallException(
        'إعدادات الاتصال غير مكتملة. يرجى التحقق من App ID الخاص بخدمة Agora.',
        cause: error,
      );
    }
  }

  String _maskAppId(String appId) {
    final trimmed = appId.trim();
    if (trimmed.length <= 6) {
      return '***';
    }
    final prefix = trimmed.substring(0, 3);
    final suffix = trimmed.substring(trimmed.length - 3);
    return '$prefix***$suffix';
  }

  Future<void> _ensureEngineInitialized({required bool enableVideo}) async {
    if (_isDisposing) {
      final disposeFuture = _disposeFuture;
      if (disposeFuture != null) {
        _log('Waiting for engine dispose to finish before reinitializing.');
        await disposeFuture;
      }
    }

    final existingEngine = _engine;
    if (existingEngine != null && !_isEngineReleased) {
      if (enableVideo) {
        await existingEngine.enableVideo();
      }
      return;
    }

    if (_initializationFuture != null) {
      _log('Awaiting in-flight Agora engine initialization.');
      await _initializationFuture;
      if (enableVideo) {
        await _engine?.enableVideo();
      }
      return;
    }

    final appId = _obtainAppId();
    _log('Initializing Agora engine (enableVideo=$enableVideo)...');
    final future = _createAndInitializeEngine(
      appId: appId,
      enableVideo: enableVideo,
    );
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _createAndInitializeEngine({
    required String appId,
    required bool enableVideo,
  }) async {
    final engine = createAgoraRtcEngine();
    try {
      await engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );
    } on AgoraRtcException catch (error) {
      _log('Failed to initialize Agora engine: code=${error.code} message=${error.message}');
      throw AgoraCallException(
        'تعذر تهيئة خدمة المكالمات، يرجى المحاولة مرة أخرى.',
        cause: error,
        agoraErrorCode: error.code,
      );
    } catch (error) {
      _log('Unexpected error while initializing Agora engine: $error');
      throw AgoraCallException(
        'تعذر تهيئة خدمة المكالمات، يرجى المحاولة مرة أخرى.',
        cause: error,
      );
    }

    await engine.enableAudio();
    if (enableVideo) {
      await engine.enableVideo();
    }

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          _log(
            'onJoinChannelSuccess: ${connection.channelId} uid=${connection.localUid} elapsed=$elapsed',
          );
          _isJoined = true;
          _isJoining = false;
          _currentChannelId = connection.channelId;
          _localUid = connection.localUid;
          isLocalUserJoined.value = true;
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          _log('onLeaveChannel: ${connection.channelId}');
          _isJoined = false;
          _isJoining = false;
          _currentChannelId = null;
          _localUid = null;
          _isVideoCall = false;
          isLocalUserJoined.value = false;
          isMuted.value = false;
          isSpeakerEnabled.value = false;
          remoteUserIds.value = <int>{};
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _log(
            'onUserJoined: ${connection.channelId} remoteUid=$remoteUid elapsed=$elapsed',
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
            'onUserOffline: ${connection.channelId} remoteUid=$remoteUid reason=${reason.name}',
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
          _log('Connection lost for ${connection.channelId}');
        },
        onError: (ErrorCodeType error, String message) {
          final code = error.value();
          _lastEngineErrorCode = code;
          _log('AGORA onError: code=$code message=$message type=${error.name}');
        },
      ),
    );

    _engine = engine;
    _isInitialized = true;
    _isEngineReleased = false;
    _log('Agora engine initialized (appId=${_maskAppId(appId)}).');
  }

  Future<void> joinChannel({
    required String channelId,
    required String? token,
    required int uid,
    required bool withVideo,
  }) async {
    if (channelId.trim().isEmpty) {
      throw AgoraCallException('معرّف قناة الاتصال غير صالح.');
    }

    if (_ongoingJoin != null) {
      if (_joiningChannelId == channelId) {
        _log('Join already in progress for channel $channelId');
        return _ongoingJoin!;
      }
      try {
        await _ongoingJoin;
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    }

    final joinFuture = _performJoin(
      channelId: channelId,
      token: token,
      uid: uid,
      withVideo: withVideo,
    );
    _ongoingJoin = joinFuture;
    _joiningChannelId = channelId;
    try {
      await joinFuture;
    } finally {
      if (identical(_ongoingJoin, joinFuture)) {
        _ongoingJoin = null;
        _joiningChannelId = null;
      }
    }
  }

  @visibleForTesting
  Future<void> startCall({
    required String channelId,
    required bool isVideo,
  }) async {
    final uid = _resolveLocalUid();
    final effectiveToken = _effectiveToken(AgoraConfig.token);
    await joinChannel(
      channelId: channelId,
      token: effectiveToken,
      uid: uid,
      withVideo: isVideo,
    );
  }

  Future<void> _performJoin({
    required String channelId,
    required String? token,
    required int uid,
    required bool withVideo,
  }) async {
    _lastJoinResultCode = null;
    _lastEngineErrorCode = null;

    await _ensurePermissions(isVideo: withVideo);
    await _ensureEngineInitialized(enableVideo: withVideo);

    final engine = _requireEngine();

    if (_isDisposing) {
      _log('Cannot join channel $channelId while engine is disposing.');
      throw AgoraCallException('خدمة المكالمات غير متاحة حالياً، حاول مجددًا لاحقاً.');
    }

    if (_isJoining && _currentChannelId == channelId) {
      _log('Join already in progress for $channelId');
      return;
    }
    if (_isJoined && _currentChannelId == channelId) {
      _log('Already joined channel $channelId');
      return;
    }
    if (_isJoined && _currentChannelId != channelId) {
      await _leaveChannel(awaitOngoingJoin: false);
    }

    _isJoining = true;
    _isVideoCall = withVideo;
    _currentChannelId = channelId;
    _localUid = uid;

    isMuted.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};

    await engine.enableAudio();
    await engine.muteLocalAudioStream(false);

    if (withVideo) {
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

    final String? resolvedToken = _effectiveToken(token);
    final logTokenState = resolvedToken == null ? 'none' : 'provided';
    _log(
      'Joining channel: $channelId, uid=$uid, withVideo=$withVideo, token=$logTokenState',
    );

    try {
      await engine.joinChannel(
        token: resolvedToken,
        channelId: channelId,
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
      _lastJoinResultCode = 0;
      _log('joinChannel request issued for $channelId');
    } on AgoraRtcException catch (error) {
      _lastJoinResultCode = error.code;
      _currentChannelId = null;
      _isJoined = false;
      _localUid = null;
      isLocalUserJoined.value = false;
      remoteUserIds.value = <int>{};
      final errorCode = _errorCodeTypeFromValue(error.code);
      _log(
        'join failed: code=${error.code} message=${error.message ?? 'unknown'}',
      );
      throw AgoraCallException(
        _localizedMessageForError(
          errorCode,
          rawCode: error.code,
        ),
        cause: error,
        agoraErrorCode: error.code,
      );
    } catch (error) {
      _currentChannelId = null;
      _isJoined = false;
      _localUid = null;
      isLocalUserJoined.value = false;
      remoteUserIds.value = <int>{};
      _log('joinChannel failed with unexpected error: $error');
      throw AgoraCallException(
        'تعذر الاتصال بالمكالمة. حاول مرة أخرى.',
        cause: error,
      );
    } finally {
      if (!_isJoined) {
        _isJoining = false;
      }
    }
  }

  Future<void> leaveChannel() => _leaveChannel(awaitOngoingJoin: true);

  Future<void> _leaveChannel({required bool awaitOngoingJoin}) async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    if (awaitOngoingJoin && _ongoingJoin != null) {
      try {
        await _ongoingJoin;
      } catch (_) {
        // Ignore join errors when leaving.
      }
    }

    _log('Leaving Agora channel (channel=$_currentChannelId)');
    if (_isJoined || _isJoining) {
      try {
        await engine.leaveChannel();
      } catch (error) {
        _log('leaveChannel error: $error');
        rethrow;
      }
    }
    if (_isVideoCall) {
      await engine.stopPreview();
    }
    await engine.disableVideo();

    _isJoined = false;
    _isJoining = false;
    _isVideoCall = false;
    _currentChannelId = null;
    _localUid = null;
    isMuted.value = false;
    isSpeakerEnabled.value = false;
    isLocalUserJoined.value = false;
    remoteUserIds.value = <int>{};
  }

  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    final engine = _engine;
    if (engine == null) {
      return Future.value();
    }

    _log('Disposing Agora engine...');
    _isDisposing = true;
    final future = () async {
      try {
        await leaveChannel();
      } catch (error) {
        _log('Error while leaving channel during dispose: $error');
      }
      try {
        await engine.release();
      } catch (error) {
        _log('Failed to release engine $error');
      }
      _engine = null;
      _isInitialized = false;
      _isEngineReleased = true;
      _isDisposing = false;
      _initializationFuture = null;
      _ongoingJoin = null;
      _joiningChannelId = null;
      _disposeFuture = null;
      _log('Agora engine disposed.');
    }();

    _disposeFuture = future;
    return future;
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

  String? _normalizeToken(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? _effectiveToken(String? override) {
    final normalizedOverride = _normalizeToken(override);
    if (normalizedOverride != null) {
      return normalizedOverride;
    }
    return _normalizeToken(AgoraConfig.token);
  }
}
