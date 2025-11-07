import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Type of DM call being placed.
enum DmCallType { voice, video }

/// Lightweight participant descriptor for a DM call session.
@immutable
class DmCallParticipant {
  const DmCallParticipant({
    required this.uid,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    required this.state,
  });

  final String uid;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final String state;

  bool get isRinging => state == 'ringing';
  bool get isJoined =>
      state == 'joined' || state == 'in-progress' || state == 'active';
  bool get isEnded => state == 'ended';

  DmCallParticipant copyWith({
    String? displayName,
    String? avatarUrl,
    String? role,
    String? state,
  }) {
    return DmCallParticipant(
      uid: uid,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      state: state ?? this.state,
    );
  }
}

/// Immutable call session descriptor passed to the DM call UI.
@immutable
class DmCallSession {
  const DmCallSession({
    required this.callId,
    required this.threadId,
    required this.channelId,
    required this.type,
    required this.initiatorId,
    required this.participants,
    this.status = 'ringing',
  });

  final String callId;
  final String threadId;
  final String channelId;
  final DmCallType type;
  final String initiatorId;
  final List<DmCallParticipant> participants;
  final String status;

  DmCallSession copyWith({
    List<DmCallParticipant>? participants,
    String? status,
  }) {
    return DmCallSession(
      callId: callId,
      threadId: threadId,
      channelId: channelId,
      type: type,
      initiatorId: initiatorId,
      participants: participants ?? this.participants,
      status: status ?? this.status,
    );
  }

  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  DmCallParticipant? get currentParticipant {
    final uid = _currentUserId;
    if (uid == null) {
      return null;
    }
    for (final participant in participants) {
      if (participant.uid == uid) {
        return participant;
      }
    }
    return null;
  }

  DmCallParticipant? get caller {
    for (final participant in participants) {
      if (participant.role == 'caller') {
        return participant;
      }
    }
    return null;
  }

  DmCallParticipant? get callee {
    for (final participant in participants) {
      if (participant.role == 'callee') {
        return participant;
      }
    }
    return null;
  }

  DmCallParticipant? get otherParticipant {
    final uid = _currentUserId;
    if (uid == null) {
      return participants.isNotEmpty ? participants.first : null;
    }
    for (final participant in participants) {
      if (participant.uid != uid) {
        return participant;
      }
    }
    return participants.isNotEmpty ? participants.first : null;
  }

  bool get isCurrentUserCaller => currentParticipant?.role == 'caller';

  bool get isIncomingForCurrentUser => currentParticipant?.role == 'callee';

  bool get isRingingForCurrentUser =>
      isIncomingForCurrentUser && (currentParticipant?.isRinging ?? false);

  bool get isActiveForCurrentUser => currentParticipant?.isJoined ?? false;
}
