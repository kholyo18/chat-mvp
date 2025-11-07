import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/user_profile.dart';
import 'dm_call_models.dart';
import 'dm_call_page.dart';

/// Service responsible for orchestrating DM call sessions.
class DmCallService {
  DmCallService({
    cf.FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uuid? uuid,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _uuid = uuid ?? const Uuid();

  final cf.FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uuid _uuid;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<cf.QuerySnapshot<Map<String, dynamic>>>?
      _incomingCallsSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _listeningUid;
  bool _incomingListenerInitialized = false;
  final Set<String> _handledIncomingCallIds = <String>{};

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
    );

    final nav = navigator;
    if (nav == null) {
      throw StateError('No navigator available to present the call screen');
    }

    await nav.push(
      MaterialPageRoute<void>(
        builder: (_) => DmCallPage(session: session),
        settings: RouteSettings(name: '/dm/call/${session.callId}'),
      ),
    );
  }

  /// Starts listening for incoming DM calls targeting the signed-in user.
  void listenForIncomingCalls({
    required GlobalKey<NavigatorState> navigatorKey,
  }) {
    _navigatorKey = navigatorKey;
    if (_incomingListenerInitialized) {
      return;
    }
    _incomingListenerInitialized = true;
    _authSubscription =
        _auth.userChanges().listen(_handleAuthStateChanged, onError: (error) {
      debugPrint('DmCallService auth listener error: $error');
    });
    _handleAuthStateChanged(_auth.currentUser);
  }

  void _handleAuthStateChanged(User? user) {
    final uid = user?.uid;
    if (uid == _listeningUid) {
      return;
    }
    _listeningUid = uid;
    _incomingCallsSubscription?.cancel();
    _incomingCallsSubscription = null;
    _handledIncomingCallIds.clear();
    if (uid == null) {
      return;
    }
    _incomingCallsSubscription = _firestore
        .collection('calls')
        .where('mode', isEqualTo: 'dm')
        .where('ringingTargets', arrayContains: uid)
        .snapshots()
        .listen(
      _handleIncomingSnapshot,
      onError: (error, stack) {
        debugPrint('DmCallService incoming call listener error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      },
    );
  }

  void _handleIncomingSnapshot(
    cf.QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      final callId = doc.id;
      if (change.type == cf.DocumentChangeType.removed) {
        _handledIncomingCallIds.remove(callId);
        continue;
      }
      final data = doc.data();
      if (data == null) {
        continue;
      }
      final status = (data['status'] as String?) ?? 'ringing';
      if (status != 'ringing') {
        _handledIncomingCallIds.remove(callId);
        continue;
      }
      if (_handledIncomingCallIds.contains(callId)) {
        continue;
      }
      final session = _sessionFromData(callId, data);
      if (session == null) {
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

  Future<void> _presentIncomingCall(DmCallSession session) async {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      debugPrint('DmCallService: No navigator to present incoming DM call');
      _handledIncomingCallIds.remove(session.callId);
      return;
    }
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => DmCallPage(session: session),
          settings: RouteSettings(name: '/dm/call/${session.callId}'),
        ),
      );
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
    _authSubscription?.cancel();
    _incomingCallsSubscription?.cancel();
    _authSubscription = null;
    _incomingCallsSubscription = null;
    _listeningUid = null;
    _navigatorKey = null;
    _handledIncomingCallIds.clear();
    _incomingListenerInitialized = false;
  }
}
