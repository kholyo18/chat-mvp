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

    final callPayload = <String, dynamic>{
      'id': callRef.id,
      'channelId': channelId,
      'threadId': threadId,
      'mode': 'dm',
      'type': describeEnum(type),
      'initiator': currentUser.uid,
      'createdAt': now,
      'status': 'ringing',
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
}
