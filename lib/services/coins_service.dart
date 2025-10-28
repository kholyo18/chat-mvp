import 'package:cloud_firestore/cloud_firestore.dart';

class CoinsService {
  CoinsService();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> addCoinsDev({
    required String uid,
    required int amount,
    String? packageId,
    String? note,
  }) async {
    await _db.runTransaction((transaction) async {
      final userRef = _db.collection('users').doc(uid);
      final userSnap = await transaction.get(userRef);
      final current = (userSnap.data()?['coins'] ?? 0) as int;
      final next = current + amount;

      transaction.update(userRef, {'coins': next});

      final txRef = _db.collection('wallet').doc(uid).collection('tx').doc();
      transaction.set(txRef, {
        'type': 'purchase',
        'amount': amount,
        'balanceAfter': next,
        'createdAt': FieldValue.serverTimestamp(),
        'packageId': packageId,
        'note': note,
      });
    });
  }

  Future<void> spend({
    required String uid,
    required int amount,
    String? note,
  }) async {
    await _db.runTransaction((transaction) async {
      final userRef = _db.collection('users').doc(uid);
      final userSnap = await transaction.get(userRef);
      final current = (userSnap.data()?['coins'] ?? 0) as int;
      final next = current - amount;
      if (next < 0) {
        throw Exception('insufficient_coins');
      }

      transaction.update(userRef, {'coins': next});

      final txRef = _db.collection('wallet').doc(uid).collection('tx').doc();
      transaction.set(txRef, {
        'type': 'spend',
        'amount': -amount,
        'balanceAfter': next,
        'createdAt': FieldValue.serverTimestamp(),
        'packageId': null,
        'note': note,
      });
    });
  }

  Stream<int> coinsStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map(
          (snapshot) => (snapshot.data()?['coins'] ?? 0) as int,
        );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> txStream(String uid) {
    return _db
        .collection('wallet')
        .doc(uid)
        .collection('tx')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}
