import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _timestampToDate(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  return 0;
}

/// Immutable representation of a wallet transaction stored in Firestore.
class CoinTransaction {
  const CoinTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.note,
    required this.createdAt,
    required this.actor,
    required this.snapshot,
  });

  factory CoinTransaction.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};
    return CoinTransaction(
      id: snapshot.id,
      type: (data['type'] as String? ?? '').trim(),
      amount: _toInt(data['amount']),
      balanceAfter: _toInt(data['balanceAfter']),
      note: (data['note'] as String? ?? '').trim(),
      createdAt: _timestampToDate(data['createdAt']),
      actor: (data['actor'] as String? ?? '').trim(),
      snapshot: snapshot,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'amount': amount,
      'balanceAfter': balanceAfter,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'actor': actor,
    };
  }

  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final String note;
  final DateTime createdAt;
  final String actor;
  final DocumentSnapshot<Map<String, dynamic>> snapshot;

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;
}
