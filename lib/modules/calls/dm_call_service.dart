import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../config/agora_config.dart';
import '../../models/user_profile.dart';
import 'agora_call_client.dart';
import 'dm_call_models.dart';
import 'dm_call_page.dart';

/// Service responsible for orchestrating DM call sessions.
class DmCallService {
  DmCallService._({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

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
    final channelId = 'dm_call_${callRef.id}';
    final callerAgoraUid = _agoraClient.agoraUidForUser(currentUser.uid);
    final calleeAgoraUid = _agoraClient.agoraUidForUser(otherUserId);

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
        if (AgoraConfig.token != null) 'token': AgoraConfig.token,
      },
    };

    await callRef.set(callPayload);

    try {
      debugPrint(
        'DmCallService: Initiating ${type == DmCallType.video ? 'video' : 'voice'} call $channelId (callId=${callRef.id}, localUid=$callerAgoraUid, remoteUid=$calleeAgoraUid)',
      );
      await _agoraClient.joinDmCall(
        channelId: channelId,
        token: AgoraConfig.token,
        uid: callerAgoraUid,
        isVideo: type == DmCallType.video,
      );
      await callRef.update(<String, dynamic>{
        'participants.${currentUser.uid}.state': 'joined',
        'participants.${currentUser.uid}.joinedAt': cf.FieldValue.serverTimestamp(),
      });
    } catch (error, stack) {
      debugPrint('DmCallService: Failed to join Agora for call ${callRef.id}: $error');
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      try {
        await callRef.delete();
      } catch (deleteError, deleteStack) {
        debugPrint('DmCallService: Failed to delete call ${callRef.id} after Agora error: $deleteError');
        FlutterError.reportError(
          FlutterErrorDetails(exception: deleteError, stack: deleteStack),
        );
      }
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
      agoraToken: AgoraConfig.token,
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
      channelId = callId;
    }
    return DmCallSession(
      callId: callId,
      threadId: (data['threadId'] as String?) ?? callId,
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
    final callRef = _firestore.collection('calls').doc(call.callId);
    final shouldActivate = call.status != 'active';
    final preJoinPayload = <String, dynamic>{
      'participants.$uid.state': 'joining',
      'ringingTargets': cf.FieldValue.arrayRemove(<String>[uid]),
    };
    await callRef.update(preJoinPayload);
    try {
      debugPrint(
        'DmCallService: Answering call ${call.callId} by joining channel ${call.channelId} (localUid=$localAgoraUid)',
      );
      final token = call.agoraToken ?? AgoraConfig.token;
      await _agoraClient.joinDmCall(
        channelId: call.channelId,
        token: token,
        uid: localAgoraUid,
        isVideo: call.type == DmCallType.video,
      );
      final postJoinPayload = <String, dynamic>{
        'participants.$uid.state': 'joined',
        'participants.$uid.joinedAt': cf.FieldValue.serverTimestamp(),
      };
      if (shouldActivate) {
        postJoinPayload['status'] = 'active';
      }
      await callRef.update(postJoinPayload);
    } catch (error) {
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
      } catch (updateError, stack) {
        debugPrint('DmCallService: Failed to revert call state after Agora error: $updateError');
        FlutterError.reportError(
          FlutterErrorDetails(exception: updateError, stack: stack),
        );
      }
      rethrow;
    }
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

  Future<void> _teardownAgora(String _) async {
    try {
      await _agoraClient.leaveCurrentCall();
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
    unawaited(_agoraClient.dispose());
    stopListening();
    _navigatorKey = null;
  }
}
