import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/coin_transaction.dart';

class WalletServiceException implements Exception {
  WalletServiceException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() =>
      'WalletServiceException(code: $code, message: $message, cause: $cause)';
}

class WalletInsufficientBalanceException extends WalletServiceException {
  WalletInsufficientBalanceException()
      : super('Insufficient balance', code: 'insufficient-balance');
}

class WalletException extends WalletServiceException {
  WalletException(String message, {String? code, Object? cause})
      : super(message, code: code, cause: cause);
}

class WalletService {
  WalletService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<int> coinsStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return 0;
      }
      final raw = data['coins'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) {
        return int.tryParse(raw) ?? 0;
      }
      return 0;
    });
  }

  Future<int> earn(
    int amount, {
    String? uid,
    String note = 'earn',
  }) {
    if (amount <= 0) {
      throw WalletServiceException('Earn amount must be positive');
    }
    return _applyDelta(
      uid: _resolveUid(uid),
      delta: amount,
      type: 'earn',
      note: note,
    );
  }

  Future<int> spend(
    int amount, {
    String? uid,
    String note = 'spend',
  }) {
    if (amount <= 0) {
      throw WalletServiceException('Spend amount must be positive');
    }
    return _applyDelta(
      uid: _resolveUid(uid),
      delta: -amount,
      type: 'spend',
      note: note,
    );
  }

  Future<int> upgradeVip(
    String tier, {
    required int price,
    String? uid,
    String note = 'vip upgrade',
  }) {
    if (price <= 0) {
      throw WalletServiceException('VIP upgrade price must be positive');
    }
    final normalizedTier = tier.trim().toLowerCase();
    if (normalizedTier.isEmpty) {
      throw WalletServiceException('VIP tier must be provided');
    }
    return _applyDelta(
      uid: _resolveUid(uid),
      delta: -price,
      type: 'vip_upgrade',
      note: note,
      vipTier: normalizedTier,
    );
  }

  Future<List<CoinTransaction>> fetchPage({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(uid)
        .collection('wallet_transactions')
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    return snapshot.docs.map(CoinTransaction.fromSnapshot).toList();
  }

  String _resolveUid(String? uid) {
    if (uid != null && uid.isNotEmpty) {
      return uid;
    }
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      throw WalletServiceException('No signed-in user', code: 'unauthenticated');
    }
    return current.uid;
  }

  Future<int> _applyDelta({
    required String uid,
    required int delta,
    required String type,
    required String note,
    String? vipTier,
  }) async {
    try {
      final callable = _functions.httpsCallable('walletTxn');
      final response = await callable.call(<String, dynamic>{
        'uid': uid,
        'delta': delta,
        'type': type,
        'note': note,
        if (vipTier != null) 'vipTier': vipTier,
      });
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final balanceRaw = data['balance'];
        if (balanceRaw is int) return balanceRaw;
        if (balanceRaw is num) return balanceRaw.toInt();
      }
    } on FirebaseFunctionsException catch (error) {
      final code = error.code;
      if (code == 'failed-precondition') {
        throw WalletException(
          'Precondition failed',
          code: code,
          cause: error,
        );
      } else if (code == 'permission-denied') {
        throw WalletException(
          'Permission denied',
          code: code,
          cause: error,
        );
      } else if (code == 'unauthenticated') {
        throw WalletException(
          'Please sign in',
          code: code,
          cause: error,
        );
      } else {
        throw WalletException(
          'Wallet error: $code',
          code: code,
          cause: error,
        );
      }
    } on Object {
      // Fall back to client transaction.
    }

    return _applyDeltaViaTransaction(
      uid: uid,
      delta: delta,
      type: type,
      note: note,
      vipTier: vipTier,
    );
  }

  Future<int> _applyDeltaViaTransaction({
    required String uid,
    required int delta,
    required String type,
    required String note,
    String? vipTier,
  }) async {
    try {
      return await _firestore.runTransaction<int>((transaction) async {
        final userRef = _firestore.collection('users').doc(uid);
        final userSnapshot = await transaction.get(userRef);
        final userData = userSnapshot.data() ?? <String, dynamic>{};
        final currentRaw = userData['coins'];
        final current = currentRaw is int
            ? currentRaw
            : currentRaw is num
                ? currentRaw.toInt()
                : currentRaw is String
                    ? int.tryParse(currentRaw) ?? 0
                    : 0;
        final next = current + delta;
        if (next < 0) {
          throw WalletInsufficientBalanceException();
        }

        final txRef = userRef.collection('wallet_transactions').doc();
        final createdAt = FieldValue.serverTimestamp();
        final payload = <String, dynamic>{
          'type': type,
          'amount': delta,
          'balanceAfter': next,
          'note': note,
          'createdAt': createdAt,
          'actor': 'user',
        };

        transaction.set(txRef, payload);

        final updates = <String, dynamic>{
          'coins': next,
        };
        if (type == 'vip_upgrade' && vipTier != null && vipTier.isNotEmpty) {
          updates['vipTier'] = vipTier;
          updates['vipSince'] = createdAt;
        }

        transaction.set(userRef, updates, SetOptions(merge: true));
        return next;
      });
    } on WalletInsufficientBalanceException {
      rethrow;
    } catch (error, stackTrace) {
      throw WalletServiceException(
        'Failed to apply wallet transaction',
        code: 'transaction-failed',
        cause: _WalletErrorDetails(error, stackTrace),
      );
    }
  }
}

class _WalletErrorDetails {
  const _WalletErrorDetails(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'error: $error\n$stackTrace';
}
