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
  bool get isJoined => state == 'joined' || state == 'in-progress';
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
  });

  final String callId;
  final String threadId;
  final String channelId;
  final DmCallType type;
  final String initiatorId;
  final List<DmCallParticipant> participants;

  DmCallSession copyWith({
    List<DmCallParticipant>? participants,
  }) {
    return DmCallSession(
      callId: callId,
      threadId: threadId,
      channelId: channelId,
      type: type,
      initiatorId: initiatorId,
      participants: participants ?? this.participants,
    );
  }
}
