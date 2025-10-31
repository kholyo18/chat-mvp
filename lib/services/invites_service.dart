import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_functions/cloud_functions.dart';

class InviteCodeInfo {
  const InviteCodeInfo({
    required this.code,
    required this.uses,
    this.maxUses,
    this.expiresAt,
    this.createdAt,
    this.createdBy,
  });

  final String code;
  final int uses;
  final int? maxUses;
  final cf.Timestamp? expiresAt;
  final cf.Timestamp? createdAt;
  final String? createdBy;
}

class InviteRedeemResult {
  const InviteRedeemResult({
    required this.joined,
    this.alreadyMember = false,
    this.roomId,
  });

  final bool joined;
  final bool alreadyMember;
  final String? roomId;
}

class InvitesService {
  InvitesService._();

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<String> createInvite({
    required String roomId,
    int? maxUses,
    cf.Timestamp? expiresAt,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final callable = _functions.httpsCallable('createInviteCode');
    final payload = <String, Object?>{'roomId': roomId};
    if (maxUses != null) {
      payload['maxUses'] = maxUses;
    }
    if (expiresAt != null) {
      payload['expiresAt'] = expiresAt.toDate().toIso8601String();
    }
    try {
      final response = await callable.call(payload).timeout(timeout);
      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['code'] is! String) {
        // CODEX-BEGIN:COMPILE_FIX::invites-func-ex
        throw FirebaseFunctionsException(code: 'invalid-response', message: 'Missing code in response');
        // CODEX-END:COMPILE_FIX::invites-func-ex
      }
      return data['code'] as String;
    } on TimeoutException {
      // CODEX-BEGIN:COMPILE_FIX::invites-func-ex
      throw FirebaseFunctionsException(code: 'deadline-exceeded', message: 'Invite creation timed out');
      // CODEX-END:COMPILE_FIX::invites-func-ex
    }
  }

  static Future<List<InviteCodeInfo>> listInvites({
    required String roomId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final callable = _functions.httpsCallable('listRoomInvites');
    try {
      final response = await callable.call({'roomId': roomId}).timeout(timeout);
      final data = response.data as Map<String, dynamic>?;
      final invitesRaw = data?['invites'];
      if (invitesRaw is! List) {
        return const <InviteCodeInfo>[];
      }
      return invitesRaw.map((item) {
        if (item is! Map) {
          return const InviteCodeInfo(code: '', uses: 0);
        }
        final map = Map<String, dynamic>.from(item as Map);
        final usesRaw = map['uses'];
        final maxUsesRaw = map['maxUses'];
        return InviteCodeInfo(
          code: (map['code'] ?? '') as String,
          uses: usesRaw is num ? usesRaw.toInt() : 0,
          maxUses: maxUsesRaw is num ? maxUsesRaw.toInt() : null,
          expiresAt: _parseTimestamp(map['expiresAt']),
          createdAt: _parseTimestamp(map['createdAt']),
          createdBy: map['createdBy'] as String?,
        );
      }).where((invite) => invite.code.isNotEmpty).toList();
    } on TimeoutException {
      // CODEX-BEGIN:COMPILE_FIX::invites-func-ex
      throw FirebaseFunctionsException(code: 'deadline-exceeded', message: 'Invite list timed out');
      // CODEX-END:COMPILE_FIX::invites-func-ex
    }
  }

  static Future<InviteRedeemResult> redeemInvite({
    required String code,
    String? displayName,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final callable = _functions.httpsCallable('redeemInviteCode');
    try {
      final response = await callable
          .call(<String, Object?>{'code': code, if (displayName != null) 'displayName': displayName})
          .timeout(timeout);
      final data = response.data as Map<String, dynamic>?;
      final joined = data?['joined'] == true;
      final alreadyMember = data?['alreadyMember'] == true;
      final roomId = data?['roomId'] as String?;
      return InviteRedeemResult(joined: joined, alreadyMember: alreadyMember, roomId: roomId);
    } on TimeoutException {
      // CODEX-BEGIN:COMPILE_FIX::invites-func-ex
      throw FirebaseFunctionsException(code: 'deadline-exceeded', message: 'Invite redemption timed out');
      // CODEX-END:COMPILE_FIX::invites-func-ex
    }
  }

  static cf.Timestamp? _parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is cf.Timestamp) return raw;
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return cf.Timestamp.fromDate(parsed.toUtc());
      }
    }
    if (raw is int) {
      return cf.Timestamp.fromMillisecondsSinceEpoch(raw);
    }
    return null;
  }
}
