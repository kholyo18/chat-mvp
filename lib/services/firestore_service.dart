// CODEX-BEGIN:STORE_FIRESTORE_SERVICE
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

sealed class SafeResult<T> {
  const SafeResult();
}

class SafeSuccess<T> extends SafeResult<T> {
  const SafeSuccess(this.value);

  final T value;
}

class SafeFailure<T> extends SafeResult<T> {
  const SafeFailure({
    required this.error,
    required this.stackTrace,
    required this.message,
  });

  final Object error;
  final StackTrace stackTrace;
  final String message;
}

Future<SafeResult<T>> safeRequest<T>(
  Future<T> Function() request, {
  String? debugLabel,
}) async {
  try {
    final value = await request();
    return SafeSuccess<T>(value);
  } catch (err, stack) {
    final label = debugLabel ?? T.toString();
    debugPrint('safeRequest($label) failed: $err');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: err,
        stack: stack,
        informationCollector: () => [
          if (debugLabel != null)
            DiagnosticsProperty<String>('safeRequest.label', debugLabel),
        ],
      ),
    );
    return SafeFailure<T>(
      error: err,
      stackTrace: stack,
      message: err is Exception ? err.toString() : '$err',
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _parseDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic> _cloneMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(source);
}

class StoreItem {
  const StoreItem({
    required this.id,
    required this.coins,
    this.label,
    this.price,
    this.sku,
    this.createdAt,
    required this.raw,
  });

  final String id;
  final int coins;
  final String? label;
  final double? price;
  final String? sku;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory StoreItem.fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = _cloneMap(doc.data());
    final dynamic coinsRaw = data['coins'] ?? data['amount'] ?? data['quantity'];
    final dynamic priceRaw = data['price'] ?? data['fiatPrice'] ?? data['amountFiat'];
    final dynamic skuRaw = data['sku'] ?? data['productId'] ?? data['skuId'];
    final dynamic labelRaw = data['label'] ?? data['title'] ?? data['name'];
    final createdAt = _parseDateTime(data['createdAt']);

    return StoreItem(
      id: doc.id,
      coins: _parseInt(coinsRaw),
      label: labelRaw is String ? labelRaw : null,
      price: _parseDouble(priceRaw),
      sku: skuRaw is String ? skuRaw : skuRaw?.toString(),
      createdAt: createdAt,
      raw: Map<String, dynamic>.unmodifiable(data),
    );
  }

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    final rawData = json['raw'];
    Map<String, dynamic> raw = const {};
    if (rawData is Map<String, dynamic>) {
      raw = Map<String, dynamic>.from(rawData);
    } else if (rawData is Map) {
      raw =
          Map<String, dynamic>.from(rawData as Map<dynamic, dynamic>);
    }
    return StoreItem(
      id: (json['id'] as String?) ?? '',
      coins: _parseInt(json['coins']),
      label: json['label'] as String?,
      price: _parseDouble(json['price']),
      sku: (json['sku'] as String?) ?? raw['sku']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt())
          : _parseDateTime(raw['createdAt']),
      raw: Map<String, dynamic>.unmodifiable(raw),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'coins': coins,
      if (label != null) 'label': label,
      if (price != null) 'price': price,
      if (sku != null) 'sku': sku,
      if (createdAt != null) 'createdAt': createdAt!.millisecondsSinceEpoch,
      'raw': raw,
    };
  }
}

class StorePagePayload {
  const StorePagePayload({
    required this.items,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<StoreItem> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<StorePagePayload> fetchStorePage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('store')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final docs = snapshot.docs;
    final items = docs.map(StoreItem.fromDocument).toList();
    final last = docs.isNotEmpty ? docs.last : startAfter;
    final hasMore = docs.length == limit;
    return StorePagePayload(items: items, lastDocument: last, hasMore: hasMore);
  }
}
// CODEX-END:STORE_FIRESTORE_SERVICE
