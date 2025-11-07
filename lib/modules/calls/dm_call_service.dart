import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/user_profile.dart';
import 'agora_call_client.dart';
import 'dm_call_models.dart';
import 'dm_call_page.dart';

/// Service responsible for orchestrating DM call sessions.
class DmCallService {
  DmCallService._({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uuid? uuid,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _uuid = uuid ?? const Uuid();

  factory DmCallService({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uuid? uuid,
  }) {
    if (firestore != null || auth != null || uuid != null) {
      return DmCallService._(
        firestore: firestore,
        auth: auth,
        uuid: uuid,
      );
    }
    return instance;
  }

  static final DmCallService instance = DmCallService._();

  final cf.FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid;
  StreamSubscription<cf.QuerySnapshot<Map<String, dynamic>>>?
      _incomingCallsSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _listeningUid;
  final Set<String> _handledIncomingCallIds = <String>{};
  final Set<String> _activeCallRouteIds = <String>{};
  final AgoraCallClient _agoraClient = AgoraCallClient.instance;
  String? _activeAgoraCallId;
  String? _joiningAgoraCallId;

  Future<void> startVoiceCallWithUser(
    String threadId,
    String otherUserId, {
    NavigatorState? navigator,
  }) async {
    await _startCall(
      threadId: threadId,
      otherUserId: otherUserId,
      type: DmCallType.voice,
      navigator: navigator,
    );
  }

  Future<void> startVideoCallWithUser(
    String threadId,
    String otherUserId, {
    NavigatorState? navigator,
  }) async {
    await _startCall(
      threadId: threadId,
      otherUserId: otherUserId,
      type: DmCallType.video,
      navigator: navigator,
    );
  }

  Future<void> _startCall({
    required String threadId,
    required String otherUserId,
    required DmCallType type,
    NavigatorState? navigator,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('User must be signed in to start a call');
    }

    final callRef = _firestore.collection('calls').doc();
    final now = cf.FieldValue.serverTimestamp();
    final channelId = _uuid.v4();

    UserProfile? otherProfile;
    try {
      final snap = await _firestore.collection('users').doc(otherUserId).get();
      if (snap.data() != null) {
        otherProfile = UserProfile.fromJson(snap.data()!);
      }
    } catch (err, stack) {
      debugPrint('Failed to load callee profile: $err');
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
      'state': 'joined',
      'joinedAt': now,
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
      'type': describeEnum(type),
      'initiator': currentUser.uid,
      'createdAt': now,
      'status': 'ringing',
      'participantIds': participantIds,
      'ringingTargets': <String>[otherUserId],
      'participants': <String, dynamic>{
        currentUser.uid: callerParticipant,
        otherUserId: calleeParticipant,
      },
    };

    await callRef.set(callPayload);

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
    );

    final nav = navigator;
    if (nav == null) {
      throw StateError('No navigator available to present the call screen');
    }

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => DmCallPage(
          session: session,
          onAnswerIncomingCall: answerIncomingCall,
          onDeclineIncomingCall: declineIncomingCall,
          onEnsureActiveCall: ensureActiveCall,
          onTerminateCall: terminateCall,
        ),
        settings: RouteSettings(name: '/dm/call/${session.callId}'),
      ),
    );
  }

  /// Starts listening for incoming DM calls targeting [uid].
  void startListening({
    required String uid,
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    if (uid.isEmpty) {
      debugPrint('DmCallService: startListening aborted due to empty uid');
      return;
    }
    final alreadyListening =
        _incomingCallsSubscription != null && _listeningUid == uid;
    final navigatorUnchanged = identical(_navigatorKey, navigatorKey);
    _navigatorKey = navigatorKey;
    if (alreadyListening && navigatorUnchanged) {
      debugPrint('DmCallService: listener already active for uid=$uid');
      return;
    }
    stopListening();
    _listeningUid = uid;
    debugPrint('DmCallService: Subscribing for incoming DM calls (uid=$uid)');
    final query = _firestore
        .collection('calls')
        .where('mode', isEqualTo: 'dm')
        .where('status', isEqualTo: 'ringing')
        .where('participantIds', arrayContains: uid);
    _incomingCallsSubscription = query.snapshots().listen(
      (snapshot) => _handleIncomingSnapshot(snapshot, uid),
      onError: (error, stack) {
        debugPrint('DmCallService incoming call listener error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      },
    );
  }

  /// Cancels the incoming calls listener, if active.
  void stopListening() {
    if (_incomingCallsSubscription != null) {
      debugPrint('DmCallService: Stopping incoming call listener');
    }
    _incomingCallsSubscription?.cancel();
    _incomingCallsSubscription = null;
    _handledIncomingCallIds.clear();
    _activeCallRouteIds.clear();
    _listeningUid = null;
  }

  void _handleIncomingSnapshot(
    cf.QuerySnapshot<Map<String, dynamic>> snapshot,
    String targetUid,
  ) {
    final docIds = snapshot.docs.map((doc) => doc.id).join(', ');
    debugPrint(
      'DmCallService: Snapshot for $targetUid has ${snapshot.docs.length} docs [$docIds]',
    );
    if (_listeningUid != targetUid) {
      debugPrint(
        'DmCallService: Ignoring snapshot for stale uid=$targetUid (listening=$_listeningUid)',
      );
      return;
    }
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      final callId = doc.id;
      if (change.type == cf.DocumentChangeType.removed) {
        debugPrint('DmCallService: Call $callId removed from ringing snapshot');
        _handledIncomingCallIds.remove(callId);
        _activeCallRouteIds.remove(callId);
        continue;
      }
      final data = doc.data();
      if (data == null) {
        debugPrint('DmCallService: Skipping $callId because data is null');
        continue;
      }
      final status = (data['status'] as String?) ?? 'ringing';
      final endedAt = data['endedAt'];
      if (endedAt != null) {
        debugPrint('DmCallService: Ignoring $callId because endedAt=$endedAt');
        _handledIncomingCallIds.remove(callId);
        continue;
      }
      if (status != 'ringing') {
        debugPrint('DmCallService: Ignoring $callId with status=$status');
        _handledIncomingCallIds.remove(callId);
        continue;
      }
      if (_handledIncomingCallIds.contains(callId)) {
        debugPrint('DmCallService: Call $callId already handled');
        continue;
      }
      final participantsRaw = data['participants'];
      if (participantsRaw is! Map<String, dynamic>) {
        debugPrint('DmCallService: Call $callId has invalid participants payload');
        continue;
      }
      final participantRaw = participantsRaw[targetUid];
      if (participantRaw is! Map<String, dynamic>) {
        debugPrint(
          'DmCallService: Call $callId does not include participant data for $targetUid',
        );
        continue;
      }
      final role = (participantRaw['role'] as String?)?.toLowerCase();
      if (role != 'callee') {
        debugPrint(
          'DmCallService: Call $callId ignored because participant role is $role',
        );
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
      debugPrint(
        'DmCallService: Incoming ringing call $callId for $targetUid participants=[$participantsDescription]',
      );
      final session = _sessionFromData(callId, data);
      if (session == null) {
        debugPrint('DmCallService: Failed to build session for call $callId');
        continue;
      }
      _handledIncomingCallIds.add(callId);
      _presentIncomingCall(session);
    }
  }

  DmCallSession? _sessionFromData(String callId, Map<String, dynamic> data) {
    final typeRaw = (data['type'] as String?)?.toLowerCase();
    final DmCallType type = typeRaw == 'video'
        ? DmCallType.video
        : DmCallType.voice;
    final participantsRaw = data['participants'];
    final participants = _parseParticipants(participantsRaw);
    if (participants.isEmpty) {
      return null;
    }
    return DmCallSession(
      callId: callId,
      threadId: (data['threadId'] as String?) ?? callId,
      channelId: (data['channelId'] as String?) ?? callId,
      type: type,
      initiatorId: (data['initiator'] as String?) ?? '',
      participants: participants,
      status: (data['status'] as String?) ?? 'ringing',
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
    final callRef = _firestore.collection('calls').doc(call.callId);
    final payload = <String, dynamic>{
      'participants.$uid.state': 'joined',
      'participants.$uid.joinedAt': cf.FieldValue.serverTimestamp(),
      'ringingTargets': cf.FieldValue.arrayRemove(<String>[uid]),
    };
    if (call.status != 'active') {
      payload['status'] = 'active';
    }
    await callRef.update(payload);
    await ensureActiveCall(call.copyWith(status: 'active'));
  }

  Future<void> declineIncomingCall(DmCallSession call) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('User must be signed in to decline calls');
    }
    final callRef = _firestore.collection('calls').doc(call.callId);
    await callRef.update(<String, dynamic>{
      'participants.$uid.state': 'ended',
      'participants.$uid.leftAt': cf.FieldValue.serverTimestamp(),
      'ringingTargets': cf.FieldValue.arrayRemove(<String>[uid]),
      'status': 'ended',
      'endedAt': cf.FieldValue.serverTimestamp(),
    });
    await _teardownAgora(call.callId);
    _handledIncomingCallIds.remove(call.callId);
    final navigator = _navigatorKey?.currentState;
    if (navigator != null) {
      await navigator.maybePop();
    }
  }

  Future<void> ensureActiveCall(DmCallSession session) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('User must be signed in to join calls');
    }
    final status = session.status.toLowerCase();
    if (status != 'active' && status != 'in-progress') {
      return;
    }
    if (_activeAgoraCallId == session.callId) {
      return;
    }
    if (_joiningAgoraCallId == session.callId) {
      return;
    }
    _joiningAgoraCallId = session.callId;
    try {
      if (session.type == DmCallType.video) {
        await _agoraClient.startVideoCall(
          channelName: session.channelId,
          userId: uid,
        );
      } else {
        await _agoraClient.startVoiceCall(
          channelName: session.channelId,
          userId: uid,
        );
      }
      _activeAgoraCallId = session.callId;
    } finally {
      if (_joiningAgoraCallId == session.callId) {
        _joiningAgoraCallId = null;
      }
    }
  }

  Future<void> terminateCall(
    DmCallSession session, {
    bool remoteEnded = false,
  }) async {
    final uid = _auth.currentUser?.uid;
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
    }
  }

  Future<void> _teardownAgora(String callId) async {
    if (_activeAgoraCallId == callId) {
      _activeAgoraCallId = null;
    }
    if (_joiningAgoraCallId == callId) {
      _joiningAgoraCallId = null;
    }
    try {
      await _agoraClient.endCall();
    } catch (err, stack) {
      debugPrint('DmCallService: Failed to teardown Agora call: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }
  }

  Future<void> _presentIncomingCall(DmCallSession session) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('DmCallService: No navigator to present incoming DM call');
      _handledIncomingCallIds.remove(session.callId);
      return;
    }
    if (_activeCallRouteIds.contains(session.callId)) {
      debugPrint(
        'DmCallService: Call ${session.callId} is already being presented, skipping push',
      );
      return;
    }
    try {
      _activeCallRouteIds.add(session.callId);
      debugPrint('DmCallService: Presenting call ${session.callId}');
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DmCallPage(
            session: session,
            onAnswerIncomingCall: answerIncomingCall,
            onDeclineIncomingCall: declineIncomingCall,
            onEnsureActiveCall: ensureActiveCall,
            onTerminateCall: terminateCall,
          ),
          settings: RouteSettings(name: '/dm/call/${session.callId}'),
        ),
      ).whenComplete(() {
        _activeCallRouteIds.remove(session.callId);
        debugPrint('DmCallService: Call ${session.callId} route dismissed');
      });
    } catch (err, stack) {
      _handledIncomingCallIds.remove(session.callId);
      debugPrint('Failed to present DM call: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }
  }

  /// Stops any active listeners used for incoming calls.
  void dispose() {
    final activeCallId = _activeAgoraCallId;
    if (activeCallId != null) {
      unawaited(_teardownAgora(activeCallId));
    }
    stopListening();
    _navigatorKey = null;
  }
}
