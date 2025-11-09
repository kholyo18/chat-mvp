import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/agora_config.dart';
import '../../models/user_profile.dart';
import '../../navigation/app_navigator.dart';
import 'agora_call_client.dart';
import 'dm_call_models.dart';
import 'dm_call_page.dart';

/// Service responsible for orchestrating DM call sessions.
class DmCallService {
  DmCallService._({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance {
    networkQuality.value = _agoraClient.networkQuality.value;
    _networkQualityListener = () {
      networkQuality.value = _agoraClient.networkQuality.value;
    };
    _agoraClient.networkQuality.addListener(_networkQualityListener!);
    _connectionStateListener = () {
      _handleConnectionStateChanged(
        _agoraClient.connectionState.value,
      );
    };
    _agoraClient.connectionState.addListener(_connectionStateListener!);
    _remoteUserEventsSubscription =
        _agoraClient.remoteUserEvents.listen(_handleRemoteUserEvent);
  }

  factory DmCallService({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) {
    if (firestore != null || auth != null) {
      return DmCallService._(
        firestore: firestore,
        auth: auth,
      );
    }
    return instance;
  }

  static final DmCallService instance = DmCallService._();

  final cf.FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  StreamSubscription<cf.QuerySnapshot<Map<String, dynamic>>>?
      _incomingCallsSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _listeningUid;
  final Set<String> _handledIncomingCallIds = <String>{};
  final Set<String> _activeCallRouteIds = <String>{};
  final AgoraCallClient _agoraClient = AgoraCallClient.instance;
  final ValueNotifier<DmCallStatus> callStatus =
      ValueNotifier<DmCallStatus>(DmCallStatus.idle);
  final ValueNotifier<String?> callStatusMessage =
      ValueNotifier<String?>(null);
  final ValueNotifier<CallNetworkQuality> networkQuality =
      ValueNotifier<CallNetworkQuality>(CallNetworkQuality.unknown);
  final ValueNotifier<bool> isMinimized = ValueNotifier<bool>(false);
  final ValueNotifier<DmCallSession?> activeSession =
      ValueNotifier<DmCallSession?>(null);

  StreamSubscription<AgoraRemoteUserEvent>? _remoteUserEventsSubscription;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>?
      _activeCallSubscription;
  VoidCallback? _networkQualityListener;
  VoidCallback? _connectionStateListener;
  Timer? _ringtoneTimer;
  String? _ringtoneCallId;

  void _log(String message) {
    debugPrint('[DmCallService] $message');
  }

  void _logStack(StackTrace stack) {
    debugPrintStack(label: '[DmCallService] stack', stackTrace: stack);
  }

  void _handleRemoteUserEvent(AgoraRemoteUserEvent event) {
    if (activeSession.value == null) {
      return;
    }
    switch (event.type) {
      case AgoraRemoteUserEventType.joined:
        _setCallStatus(DmCallStatus.connected);
        break;
      case AgoraRemoteUserEventType.left:
        if (callStatus.value == DmCallStatus.connected) {
          _setCallStatus(DmCallStatus.reconnecting);
        }
        break;
    }
  }

  void _handleConnectionStateChanged(ConnectionStateType state) {
    if (activeSession.value == null && state != ConnectionStateType.connectionStateConnecting) {
      return;
    }
    switch (state) {
      case ConnectionStateType.connectionStateConnecting:
        if (callStatus.value != DmCallStatus.ended &&
            callStatus.value != DmCallStatus.error) {
          _setCallStatus(DmCallStatus.connecting);
        }
        break;
      case ConnectionStateType.connectionStateConnected:
        _setCallStatus(DmCallStatus.connected);
        break;
      case ConnectionStateType.connectionStateReconnecting:
        _setCallStatus(DmCallStatus.reconnecting);
        break;
      case ConnectionStateType.connectionStateFailed:
        _setCallStatus(
          DmCallStatus.error,
          message: 'تعذر الاتصال بالشبكة. حاول مرة أخرى.',
        );
        break;
      case ConnectionStateType.connectionStateDisconnected:
        if (activeSession.value != null &&
            callStatus.value != DmCallStatus.idle &&
            callStatus.value != DmCallStatus.ended) {
          _setCallStatus(DmCallStatus.ended);
        }
        if (activeSession.value != null) {
          _resetAfterCallEnd();
        }
        break;
      default:
        break;
    }
  }

  void _setCallStatus(DmCallStatus status, {String? message}) {
    if (callStatus.value == status && callStatusMessage.value == message) {
      return;
    }
    _log('Status changed to ${status.name}${message != null ? ' ($message)' : ''}');
    callStatus.value = status;
    callStatusMessage.value = message;
  }

  void _initializeActiveCallSession(DmCallSession session) {
    _stopIncomingRingtone();
    activeSession.value = session;
    _applyStatusFromSession(session);
    _activeCallSubscription?.cancel();
    _activeCallSubscription = _firestore
        .collection('calls')
        .doc(session.callId)
        .snapshots()
        .listen(
      (snapshot) => _handleActiveCallSnapshot(snapshot),
      onError: (error, stack) {
        _log('Active call listener error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      },
    );
  }

  void _handleActiveCallSnapshot(
    cf.DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      return;
    }
    final updated = _sessionFromData(snapshot.id, data);
    if (updated != null) {
      activeSession.value = updated;
      _applyStatusFromSession(updated);
      if (updated.status == 'ended') {
        _handleRemoteCallEnded();
      }
    }
  }

  void _applyStatusFromSession(DmCallSession session) {
    if (callStatus.value == DmCallStatus.error && session.status != 'ended') {
      return;
    }
    switch (session.status) {
      case 'ended':
        _setCallStatus(DmCallStatus.ended);
        break;
      case 'ringing':
        _setCallStatus(DmCallStatus.ringing);
        break;
      default:
        if (_agoraClient.remoteUserIds.value.isNotEmpty) {
          _setCallStatus(DmCallStatus.connected);
        } else {
          _setCallStatus(DmCallStatus.connecting);
        }
        break;
    }
  }

  void _handleRemoteCallEnded() {
    if (callStatus.value != DmCallStatus.ended) {
      _setCallStatus(DmCallStatus.ended);
    }
    _stopIncomingRingtone();
    unawaited(_agoraClient.leaveChannel());
    _resetAfterCallEnd();
  }

  void _resetAfterCallEnd() {
    _activeCallSubscription?.cancel();
    _activeCallSubscription = null;
    if (activeSession.value != null) {
      activeSession.value = null;
    }
    if (isMinimized.value) {
      isMinimized.value = false;
    }
    networkQuality.value = CallNetworkQuality.unknown;
    _stopIncomingRingtone();
  }

  void _startIncomingRingtone(String callId) {
    if (_ringtoneCallId == callId && _ringtoneTimer != null) {
      return;
    }
    if (activeSession.value != null) {
      return;
    }
    _stopIncomingRingtone();
    _ringtoneCallId = callId;
    unawaited(SystemSound.play(SystemSoundType.alert));
    _ringtoneTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    });
  }

  void _stopIncomingRingtone() {
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
    _ringtoneCallId = null;
  }

  void minimizeCallUI() {
    if (activeSession.value == null) {
      return;
    }
    if (!isMinimized.value) {
      isMinimized.value = true;
    }
  }

  void restoreCallUI() {
    if (isMinimized.value) {
      isMinimized.value = false;
    }
  }

  Future<void> reopenActiveCallUI() async {
    final session = activeSession.value;
    if (session == null) {
      return;
    }
    restoreCallUI();
    NavigatorState? navigator = _navigatorKey?.currentState;
    if (navigator == null || !navigator.mounted) {
      navigator = await waitForAuthenticatedNavigator();
      if (!identical(_navigatorKey, authenticatedNavigatorKey)) {
        _navigatorKey = authenticatedNavigatorKey;
      }
    }
    if (navigator.mounted) {
      await _pushCallPage(navigator, session);
    }
  }

  void updateActiveSessionFromUi(DmCallSession session) {
    final current = activeSession.value;
    if (current == null || current.callId != session.callId) {
      return;
    }
    activeSession.value = session;
    _applyStatusFromSession(session);
  }

  String statusLabelFor(DmCallStatus status, {String? message}) {
    switch (status) {
      case DmCallStatus.idle:
        return 'غير متصل';
      case DmCallStatus.ringing:
        return 'يرن…';
      case DmCallStatus.connecting:
        return 'جارٍ الاتصال…';
      case DmCallStatus.connected:
        return 'متصل';
      case DmCallStatus.reconnecting:
        return 'جارٍ إعادة الاتصال…';
      case DmCallStatus.ended:
        return 'انتهت المكالمة';
      case DmCallStatus.error:
        return message?.isNotEmpty == true
            ? message!
            : 'حدث خطأ في الاتصال';
    }
  }

  Future<void> startVoiceCall(
    String threadId,
    String calleeId,
  ) async {
    _log('startVoiceCall: threadId=$threadId calleeId=$calleeId');
    try {
      final session = await _startCall(
        threadId: threadId,
        otherUserId: calleeId,
        type: DmCallType.voice,
      );
      _log('startVoiceCall: callId=${session.callId} presented.');
    } catch (error, stack) {
      _log('startVoiceCall failed for threadId=$threadId calleeId=$calleeId -> $error');
      _logStack(stack);
      _reportStartCallError(error, stack);
      _showCallErrorSnackBar(error);
      rethrow;
    }
  }

  Future<void> startVideoCall(
    String threadId,
    String calleeId,
  ) async {
    _log('startVideoCall: threadId=$threadId calleeId=$calleeId');
    try {
      final session = await _startCall(
        threadId: threadId,
        otherUserId: calleeId,
        type: DmCallType.video,
      );
      _log('startVideoCall: callId=${session.callId} presented.');
    } catch (error, stack) {
      _log('startVideoCall failed for threadId=$threadId calleeId=$calleeId -> $error');
      _logStack(stack);
      _reportStartCallError(error, stack);
      _showCallErrorSnackBar(error);
      rethrow;
    }
  }

  @Deprecated('Use startVoiceCall instead')
  Future<void> startVoiceCallWithUser(
    String threadId,
    String otherUserId, {
    NavigatorState? navigator,
  }) async {
    assert(() {
      if (navigator != null) {
        debugPrint(
          'DmCallService.startVoiceCallWithUser: navigator parameter is deprecated and will be ignored.',
        );
      }
      return true;
    }());
    await startVoiceCall(threadId, otherUserId);
  }

  @Deprecated('Use startVideoCall instead')
  Future<void> startVideoCallWithUser(
    String threadId,
    String otherUserId, {
    NavigatorState? navigator,
  }) async {
    assert(() {
      if (navigator != null) {
        debugPrint(
          'DmCallService.startVideoCallWithUser: navigator parameter is deprecated and will be ignored.',
        );
      }
      return true;
    }());
    await startVideoCall(threadId, otherUserId);
  }

  Future<DmCallSession> _startCall({
    required String threadId,
    required String otherUserId,
    required DmCallType type,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User must be signed in to start a call');
    }

    NavigatorState? navigator = _navigatorKey?.currentState;
    if (navigator == null || !navigator.mounted) {
      navigator = await waitForAuthenticatedNavigator();
      if (!identical(_navigatorKey, authenticatedNavigatorKey)) {
        _navigatorKey = authenticatedNavigatorKey;
      }
    }
    if (!navigator.mounted) {
      throw StateError('Navigator for DM call presentation is not mounted');
    }

    final isVideoCall = type == DmCallType.video;
    _log('Ensuring Agora engine is ready (video=$isVideoCall).');
    await _agoraClient.initEngineIfNeeded(enableVideo: isVideoCall);

    final callRef = _firestore.collection('calls').doc();
    final now = cf.FieldValue.serverTimestamp();
    // Use a stable per-thread channel so caller and callee always join the same
    // Agora room without racing to generate different identifiers.
    final channelId = _channelNameForThread(threadId);
    final callerAgoraUid = _agoraClient.agoraUidForUser(currentUser.uid);
    final calleeAgoraUid = _agoraClient.agoraUidForUser(otherUserId);
    final callToken = _normalizeToken(AgoraConfig.token);

    UserProfile? otherProfile;
    try {
      final snap = await _firestore.collection('users').doc(otherUserId).get();
      if (snap.data() != null) {
        otherProfile = UserProfile.fromJson(snap.data()!);
      }
    } catch (err, stack) {
      _log('Failed to load callee profile: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }

    final callerParticipant = <String, dynamic>{
      'uid': currentUser.uid,
      'displayName': currentUser.displayName?.trim().isNotEmpty == true
          ? currentUser.displayName!.trim()
          : (currentUser.phoneNumber?.trim().isNotEmpty == true
              ? currentUser.phoneNumber!.trim()
              : (currentUser.email?.trim().isNotEmpty == true
                  ? currentUser.email!.trim()
                  : 'أنت')),
      'avatarUrl': currentUser.photoURL,
      'role': 'caller',
      'state': 'joining',
    };

    final calleeParticipant = <String, dynamic>{
      'uid': otherUserId,
      'displayName': (otherProfile?.displayName.trim().isNotEmpty == true)
          ? otherProfile!.displayName.trim()
          : otherUserId,
      'avatarUrl': otherProfile?.photoURL,
      'role': 'callee',
      'state': 'ringing',
    };

    final participantIds = <String>[currentUser.uid, otherUserId]..sort();
    final callPayload = <String, dynamic>{
      'id': callRef.id,
      'channelId': channelId,
      'threadId': threadId,
      'mode': 'dm',
      'type': type.name,
      'initiator': currentUser.uid,
      'createdAt': now,
      'status': 'ringing',
      'participantIds': participantIds,
      'ringingTargets': <String>[otherUserId],
      'participants': <String, dynamic>{
        currentUser.uid: callerParticipant,
        otherUserId: calleeParticipant,
      },
      'agora': <String, dynamic>{
        'channelId': channelId,
        'uids': <String, int>{
          currentUser.uid: callerAgoraUid,
          otherUserId: calleeAgoraUid,
        },
        if (callToken != null) 'token': callToken,
      },
    };

    try {
      await callRef.set(callPayload);
    } catch (error, stack) {
      _log('Failed to create call document for threadId=$threadId: $error');
      _logStack(stack);
      rethrow;
    }

    final participants = <DmCallParticipant>[
      DmCallParticipant(
        uid: currentUser.uid,
        displayName: callerParticipant['displayName'] as String,
        avatarUrl: callerParticipant['avatarUrl'] as String?,
        role: callerParticipant['role'] as String,
        state: callerParticipant['state'] as String,
      ),
      DmCallParticipant(
        uid: otherUserId,
        displayName: calleeParticipant['displayName'] as String,
        avatarUrl: calleeParticipant['avatarUrl'] as String?,
        role: calleeParticipant['role'] as String,
        state: calleeParticipant['state'] as String,
      ),
    ];

    final session = DmCallSession(
      callId: callRef.id,
      threadId: threadId,
      channelId: channelId,
      type: type,
      initiatorId: currentUser.uid,
      participants: participants,
      status: 'ringing',
      agoraToken: callToken,
    );

    _initializeActiveCallSession(session);

    unawaited(
      _pushCallPage(navigator, session).catchError((Object error, StackTrace stack) {
        _log('Failed to push call route ${session.callId}: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }),
    );

    try {
      _log(
        'Initiating ${type == DmCallType.video ? 'video' : 'voice'} call $channelId (callId=${callRef.id}, localUid=$callerAgoraUid, remoteUid=$calleeAgoraUid)',
      );
      _setCallStatus(DmCallStatus.connecting);
      await _agoraClient.joinChannel(
        channelId: channelId,
        token: callToken,
        uid: callerAgoraUid,
        withVideo: isVideoCall,
      );
      _log('Joined Agora channel $channelId for call ${callRef.id} (uid=$callerAgoraUid).');
      await callRef.update(<String, dynamic>{
        'participants.${currentUser.uid}.state': 'joined',
        'participants.${currentUser.uid}.joinedAt': cf.FieldValue.serverTimestamp(),
        'status': 'ringing',
      });
    } catch (error, stack) {
      _log('Failed to join Agora for call ${callRef.id}: $error');
      _logStack(stack);
      if (error is AgoraCallException && error.cause is AgoraRtcException) {
        final rtcError = error.cause as AgoraRtcException;
        _log(
          'AgoraRtcException for call ${callRef.id}: code=${rtcError.code} message=${rtcError.message}',
        );
      }
      _setCallStatus(
        DmCallStatus.error,
        message: _errorMessageForCall(error),
      );
      await _handleCallStartFailure(
        callRef: callRef,
        session: session,
        error: error,
        stack: stack,
      );
      rethrow;
    }

    return session;
  }

  Future<void> _handleCallStartFailure({
    required cf.DocumentReference<Map<String, dynamic>> callRef,
    required DmCallSession session,
    required Object error,
    required StackTrace stack,
  }) async {
    _log('Call ${session.callId} failed to start: $error');
    _logStack(stack);
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
    try {
      await callRef.update(<String, dynamic>{
        'status': 'ended',
        'endedAt': cf.FieldValue.serverTimestamp(),
        'participants.${session.initiatorId}.state': 'failed',
        'participants.${session.initiatorId}.endedAt': cf.FieldValue.serverTimestamp(),
      });
    } catch (updateError, updateStack) {
      _log('Failed to mark call ${session.callId} as ended after Agora error: $updateError');
      FlutterError.reportError(
        FlutterErrorDetails(exception: updateError, stack: updateStack),
      );
      try {
        await callRef.delete();
      } catch (deleteError, deleteStack) {
        _log('Failed to delete call ${session.callId} after Agora error: $deleteError');
        FlutterError.reportError(
          FlutterErrorDetails(exception: deleteError, stack: deleteStack),
        );
      }
    }

    try {
      await _agoraClient.leaveChannel();
    } catch (leaveError, leaveStack) {
      _log('Error while leaving Agora channel after failure: $leaveError');
      FlutterError.reportError(
        FlutterErrorDetails(exception: leaveError, stack: leaveStack),
      );
    }

    final navigator = _navigatorKey?.currentState;
    if (navigator != null && navigator.mounted && navigator.canPop()) {
      final callRouteName = '/dm/call/${session.callId}';
      navigator.popUntil((route) => route.settings.name != callRouteName);
    }
    _resetAfterCallEnd();
  }

  /// Starts listening for incoming DM calls targeting [uid].
  void startListening({
    required String uid,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    if (uid.isEmpty) {
      _log('startListening aborted due to empty uid');
      return;
    }
    final alreadyListening =
        _incomingCallsSubscription != null && _listeningUid == uid;
    final navigatorUnchanged = identical(_navigatorKey, navigatorKey);
    _navigatorKey = navigatorKey;
    if (alreadyListening && navigatorUnchanged) {
      _log('listener already active for uid=$uid');
      return;
    }
    stopListening();
    _listeningUid = uid;
    _log('Subscribing for incoming DM calls (uid=$uid)');
    final query = _firestore
        .collection('calls')
        .where('mode', isEqualTo: 'dm')
        .where('status', isEqualTo: 'ringing')
        .where('participantIds', arrayContains: uid);
    _incomingCallsSubscription = query.snapshots().listen(
      (snapshot) => _handleIncomingSnapshot(snapshot, uid),
      onError: (error, stack) {
        _log('incoming call listener error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      },
    );
  }

  /// Cancels the incoming calls listener, if active.
  void stopListening() {
    if (_incomingCallsSubscription != null) {
      _log('Stopping incoming call listener');
    }
    _incomingCallsSubscription?.cancel();
    _incomingCallsSubscription = null;
    _handledIncomingCallIds.clear();
    _activeCallRouteIds.clear();
    _listeningUid = null;
    _stopIncomingRingtone();
  }

  void _handleIncomingSnapshot(
    cf.QuerySnapshot<Map<String, dynamic>> snapshot,
    String targetUid,
  ) {
    final docIds = snapshot.docs.map((doc) => doc.id).join(', ');
    _log('Snapshot for $targetUid has ${snapshot.docs.length} docs [$docIds]');
    if (_listeningUid != targetUid) {
      _log('Ignoring snapshot for stale uid=$targetUid (listening=$_listeningUid)');
      return;
    }
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      final callId = doc.id;
      if (change.type == cf.DocumentChangeType.removed) {
        _log('Call $callId removed from ringing snapshot');
        _handledIncomingCallIds.remove(callId);
        _activeCallRouteIds.remove(callId);
        if (_ringtoneCallId == callId) {
          _stopIncomingRingtone();
        }
        continue;
      }
      final data = doc.data();
      if (data == null) {
        _log('Skipping $callId because data is null');
        continue;
      }
      final status = (data['status'] as String?) ?? 'ringing';
      final endedAt = data['endedAt'];
      if (endedAt != null) {
        _log('Ignoring $callId because endedAt=$endedAt');
        _handledIncomingCallIds.remove(callId);
        if (_ringtoneCallId == callId) {
          _stopIncomingRingtone();
        }
        continue;
      }
      if (status != 'ringing') {
        _log('Ignoring $callId with status=$status');
        _handledIncomingCallIds.remove(callId);
        if (_ringtoneCallId == callId) {
          _stopIncomingRingtone();
        }
        continue;
      }
      if (_handledIncomingCallIds.contains(callId)) {
        _log('Call $callId already handled');
        continue;
      }
      final participantsRaw = data['participants'];
      if (participantsRaw is! Map<String, dynamic>) {
        _log('Call $callId has invalid participants payload');
        continue;
      }
      final participantRaw = participantsRaw[targetUid];
      if (participantRaw is! Map<String, dynamic>) {
        _log('Call $callId does not include participant data for $targetUid');
        continue;
      }
      final role = (participantRaw['role'] as String?)?.toLowerCase();
      if (role != 'callee') {
        _log('Call $callId ignored because participant role is $role');
        continue;
      }
      final participantsDescription = participantsRaw.entries
          .map((entry) {
            final value = entry.value;
            if (value is Map<String, dynamic>) {
              final displayName = value['displayName'];
              final entryRole = value['role'];
              final entryState = value['state'];
              return '${entry.key}($entryRole/$entryState/$displayName)';
            }
            return entry.key;
          })
          .join(', ');
      _log(
        'Incoming ringing call $callId for $targetUid participants=[$participantsDescription]',
      );
      final session = _sessionFromData(callId, data);
      if (session == null) {
        _log('Failed to build session for call $callId');
        continue;
      }
      _handledIncomingCallIds.add(callId);
      _startIncomingRingtone(callId);
      _presentIncomingCall(session);
    }
  }

  DmCallSession? _sessionFromData(String callId, Map<String, dynamic> data) {
    final typeRaw = (data['type'] as String?)?.toLowerCase();
    final DmCallType type = typeRaw == 'video'
        ? DmCallType.video
        : DmCallType.voice;
    final threadIdRaw = (data['threadId'] as String?)?.trim();
    final threadId =
        (threadIdRaw == null || threadIdRaw.isEmpty) ? callId : threadIdRaw;
    final participantsRaw = data['participants'];
    final participants = _parseParticipants(participantsRaw);
    if (participants.isEmpty) {
      return null;
    }
    String channelId = (data['channelId'] as String?) ?? '';
    final dynamic agoraData = data['agora'];
    if (channelId.isEmpty && agoraData is Map<String, dynamic>) {
      final nestedId = agoraData['channelId'];
      if (nestedId is String && nestedId.isNotEmpty) {
        channelId = nestedId;
      }
    }
    String? agoraToken;
    if (agoraData is Map<String, dynamic>) {
      final tokenValue = agoraData['token'];
      if (tokenValue is String && tokenValue.trim().isNotEmpty) {
        agoraToken = tokenValue.trim();
      }
    }
    if (channelId.isEmpty) {
      channelId = _channelNameForThread(threadId);
    }
    return DmCallSession(
      callId: callId,
      threadId: threadId,
      channelId: channelId,
      type: type,
      initiatorId: (data['initiator'] as String?) ?? '',
      participants: participants,
      status: (data['status'] as String?) ?? 'ringing',
      agoraToken: agoraToken,
    );
  }

  List<DmCallParticipant> _parseParticipants(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const <DmCallParticipant>[];
    }
    final result = <DmCallParticipant>[];
    raw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final displayName = (value['displayName'] as String?)?.trim();
        final avatarUrl = (value['avatarUrl'] as String?)?.trim();
        final role = (value['role'] as String?) ?? 'participant';
        final state = (value['state'] as String?) ?? 'ringing';
        result.add(
          DmCallParticipant(
            uid: key,
            displayName: displayName?.isNotEmpty == true ? displayName! : key,
            avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
            role: role,
            state: state,
          ),
        );
      }
    });
    return result;
  }

  Future<void> answerIncomingCall(DmCallSession call) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('User must be signed in to answer calls');
    }
    final localAgoraUid = _agoraClient.agoraUidForUser(uid);
    if (call.channelId.isEmpty) {
      throw StateError('Call channelId is missing');
    }
    final isVideoCall = call.type == DmCallType.video;
    await _agoraClient.initEngineIfNeeded(enableVideo: isVideoCall);
    _initializeActiveCallSession(call);
    final callRef = _firestore.collection('calls').doc(call.callId);
    final shouldActivate = call.status != 'active';
    final preJoinPayload = <String, dynamic>{
      'participants.$uid.state': 'joining',
      'ringingTargets': cf.FieldValue.arrayRemove(<String>[uid]),
    };
    await callRef.update(preJoinPayload);
    try {
      _log(
        'Answering call ${call.callId} by joining channel ${call.channelId} (localUid=$localAgoraUid)',
      );
      final token =
          _normalizeToken(call.agoraToken) ?? _normalizeToken(AgoraConfig.token);
      _setCallStatus(DmCallStatus.connecting);
      await _agoraClient.joinChannel(
        channelId: call.channelId,
        token: token,
        uid: localAgoraUid,
        withVideo: isVideoCall,
      );
      _log('Answered call ${call.callId} by joining ${call.channelId} (uid=$localAgoraUid).');
      final postJoinPayload = <String, dynamic>{
        'participants.$uid.state': 'joined',
        'participants.$uid.joinedAt': cf.FieldValue.serverTimestamp(),
      };
      if (shouldActivate) {
        postJoinPayload['status'] = 'active';
      }
      await callRef.update(postJoinPayload);
    } catch (error, stack) {
      _log('Failed to answer call ${call.callId}: $error');
      _logStack(stack);
      final revert = <String, dynamic>{
        'participants.$uid.state': 'ringing',
        'participants.$uid.joinedAt': cf.FieldValue.delete(),
        'ringingTargets': cf.FieldValue.arrayUnion(<String>[uid]),
      };
      if (shouldActivate) {
        revert['status'] = 'ringing';
      }
      try {
        await callRef.update(revert);
      } catch (updateError, updateStack) {
        _log('Failed to revert call state after Agora error: $updateError');
        FlutterError.reportError(
          FlutterErrorDetails(exception: updateError, stack: updateStack),
        );
      }
      _setCallStatus(
        DmCallStatus.error,
        message: _errorMessageForCall(error),
      );
      _resetAfterCallEnd();
      rethrow;
    }
  }

  Future<void> declineIncomingCall(DmCallSession call) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('User must be signed in to decline calls');
    }
    _stopIncomingRingtone();
    final callRef = _firestore.collection('calls').doc(call.callId);
    await callRef.update(<String, dynamic>{
      'participants.$uid.state': 'ended',
      'participants.$uid.leftAt': cf.FieldValue.serverTimestamp(),
      'ringingTargets': cf.FieldValue.arrayRemove(<String>[uid]),
      'status': 'ended',
      'endedAt': cf.FieldValue.serverTimestamp(),
    });
    await _teardownAgora(call.callId);
    _setCallStatus(DmCallStatus.ended);
    _resetAfterCallEnd();
    _handledIncomingCallIds.remove(call.callId);
    final navigator = _navigatorKey?.currentState;
    if (navigator != null && navigator.mounted && navigator.canPop()) {
      await navigator.maybePop();
    }
  }

  Future<void> terminateCall(
    DmCallSession session, {
    bool remoteEnded = false,
  }) async {
    final uid = _auth.currentUser?.uid;
    _stopIncomingRingtone();
    final updates = <String, dynamic>{
      'ringingTargets': <String>[],
    };
    if (uid != null) {
      updates['participants.$uid.state'] = 'ended';
      updates['participants.$uid.leftAt'] = cf.FieldValue.serverTimestamp();
    }
    if (!remoteEnded) {
      updates['status'] = 'ended';
      updates['endedAt'] = cf.FieldValue.serverTimestamp();
    }
    try {
      if (updates.isNotEmpty) {
        await _firestore.collection('calls').doc(session.callId).update(updates);
      }
    } finally {
      await _teardownAgora(session.callId);
      _setCallStatus(DmCallStatus.ended);
      _resetAfterCallEnd();
    }
  }

  Future<void> _teardownAgora(String _) async {
    try {
      await _agoraClient.leaveChannel();
    } catch (err, stack) {
      _log('Failed to teardown Agora call: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }
  }

  String? _normalizeToken(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _channelNameForThread(String threadId) {
    const prefix = 'dm_call_';
    const maxLength = 64;
    final sanitized = threadId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeThreadId = sanitized.isEmpty ? 'thread' : sanitized;
    final maxThreadLength = maxLength - prefix.length;
    final truncated = safeThreadId.length > maxThreadLength
        ? safeThreadId.substring(0, maxThreadLength)
        : safeThreadId;
    return '$prefix$truncated';
  }

  Future<void> _presentIncomingCall(DmCallSession session) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      _log('No navigator to present incoming DM call');
      _handledIncomingCallIds.remove(session.callId);
      return;
    }
    if (!navigator.mounted) {
      _log('Navigator for incoming DM call is not mounted');
      _handledIncomingCallIds.remove(session.callId);
      return;
    }
    try {
      await _pushCallPage(navigator, session);
    } catch (err, stack) {
      _handledIncomingCallIds.remove(session.callId);
      _log('Failed to present DM call: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }
  }

  Future<void> _pushCallPage(
    NavigatorState navigator,
    DmCallSession session,
  ) async {
    if (!navigator.mounted) {
      _log('Navigator became unmounted before presenting call ${session.callId}');
      return;
    }
    if (_activeCallRouteIds.contains(session.callId)) {
      _log('Call ${session.callId} is already being presented, skipping push');
      return;
    }
    _activeCallRouteIds.add(session.callId);
    _log('Navigating to call ${session.callId}');
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DmCallPage(
            session: session,
            onAnswerIncomingCall: answerIncomingCall,
            onDeclineIncomingCall: declineIncomingCall,
            onTerminateCall: terminateCall,
          ),
          settings: RouteSettings(name: '/dm/call/${session.callId}'),
        ),
      );
    } finally {
      _activeCallRouteIds.remove(session.callId);
      _log('Call ${session.callId} route dismissed');
    }
  }

  void _reportStartCallError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  }

  void _showCallErrorSnackBar(Object error) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null || !navigator.mounted) {
      _log('Unable to show SnackBar for call error because navigator is unavailable: $error');
      return;
    }
    final context = navigator.context;
    if (!context.mounted) {
      _log('Navigator context is not mounted while handling call error: $error');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _log('No ScaffoldMessenger available to show call error');
      return;
    }
    final message = _errorMessageForCall(error);
    _log('Showing call error SnackBar: "$message" for error: $error');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessageForCall(Object error) {
    if (error is AgoraPermissionException) {
      final labels = error.missingPermissions
          .map((permission) {
            switch (permission) {
              case Permission.camera:
                return 'الكاميرا';
              case Permission.microphone:
                return 'الميكروفون';
              default:
                return 'الصلاحيات المطلوبة';
            }
          })
          .toSet()
          .toList();
      final labelText = labels.isEmpty ? 'الصلاحيات المطلوبة' : labels.join(' و ');
      return 'يرجى منح صلاحية $labelText للمتابعة في المكالمة.';
    }
    if (error is AgoraCallException) {
      return error.message.isNotEmpty
          ? error.message
          : 'فشل بدء المكالمة، حاول مجددًا.';
    }
    if (error is StateError) {
      final message = error.message.toLowerCase();
      if (message.contains('navigator')) {
        return 'تعذر فتح شاشة المكالمة. يرجى إعادة المحاولة من الصفحة الرئيسية.';
      }
      if (message.contains('signed in')) {
        return 'يجب تسجيل الدخول لإجراء المكالمة.';
      }
    }
    return 'فشل بدء المكالمة، حاول مجددًا.';
  }

  /// Stops any active listeners used for incoming calls.
  void dispose() {
    unawaited(_agoraClient.dispose());
    stopListening();
    _remoteUserEventsSubscription?.cancel();
    _remoteUserEventsSubscription = null;
    _activeCallSubscription?.cancel();
    _activeCallSubscription = null;
    final networkListener = _networkQualityListener;
    if (networkListener != null) {
      _agoraClient.networkQuality.removeListener(networkListener);
      _networkQualityListener = null;
    }
    final connectionListener = _connectionStateListener;
    if (connectionListener != null) {
      _agoraClient.connectionState.removeListener(connectionListener);
      _connectionStateListener = null;
    }
    _stopIncomingRingtone();
    callStatus.value = DmCallStatus.idle;
    callStatusMessage.value = null;
    networkQuality.value = CallNetworkQuality.unknown;
    activeSession.value = null;
    isMinimized.value = false;
    _navigatorKey = null;
  }
}
