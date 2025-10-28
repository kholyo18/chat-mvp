import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String kPaymentsProviderEnv =
    String.fromEnvironment('PAYMENTS_PROVIDER', defaultValue: 'auto');
const String kFunctionsRegion =
    String.fromEnvironment('FUNCTIONS_REGION', defaultValue: 'us-central1');

enum PaymentProvider { play, stripe }

class CoinsConfig {
  CoinsConfig({
    required this.rate,
    required this.currency,
    required this.dailyLimitCoins,
    required this.playSkus,
  });

  factory CoinsConfig.fromJson(Map<String, dynamic> data) {
    final playSkusDynamic = data['playSkus'];
    return CoinsConfig(
      rate: (data['rate'] as num?)?.toInt() ?? 100,
      currency: (data['currency'] as String?) ?? 'USD',
      dailyLimitCoins: (data['dailyLimitCoins'] as num?)?.toInt() ?? 0,
      playSkus: playSkusDynamic is Iterable
          ? playSkusDynamic.map((e) => e.toString()).toList()
          : const <String>[],
    );
  }

  final int rate;
  final String currency;
  final int dailyLimitCoins;
  final List<String> playSkus;

  double estimateFiat(int coins) {
    if (rate <= 0) {
      return 0;
    }
    return coins / rate;
  }


  int coinsForSku(String sku) {
    final digits = sku.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return 0;
    }
    return int.tryParse(digits) ?? 0;
  }
}

class PaymentsService {
  PaymentsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Uri _endpoint(String path) {
    final app = Firebase.app();
    final projectId = app.options.projectId;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('https://$kFunctionsRegion-$projectId.cloudfunctions.net$normalized');
  }

  Future<String?> _idToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Map<String, String> _headers({String? idToken}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (idToken != null) {
      headers['Authorization'] = 'Bearer $idToken';
    }
    return headers;
  }

  Future<CoinsConfig> fetchConfig() async {
    final token = await _idToken();
    final response = await _client.get(
      _endpoint('/coinsConfig'),
      headers: _headers(idToken: token),
    );
    if (response.statusCode >= 400) {
      throw Exception('Failed to load coins config (${response.statusCode})');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CoinsConfig.fromJson(data);
  }

  Future<Uri> createStripeCheckout({
    required int coins,
    required Uri successUrl,
    required Uri cancelUrl,
    String? packageId,
  }) async {
    final token = await _idToken();
    if (token == null) {
      throw Exception('auth_required');
    }
    final response = await _client.post(
      _endpoint('/createCheckoutSession'),
      headers: _headers(idToken: token),
      body: jsonEncode({
        'coins': coins,
        'successUrl': successUrl.toString(),
        'cancelUrl': cancelUrl.toString(),
        if (packageId != null) 'packageId': packageId,
      }),
    );

    if (response.statusCode == 403) {
      throw PaymentsLimitException();
    }
    if (response.statusCode >= 400) {
      throw Exception('Stripe session failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null) {
      throw Exception('Missing checkout URL');
    }
    return Uri.parse(url);
  }

  Future<void> verifyPlayPurchase({
    required String purchaseToken,
    required String productId,
    String? orderId,
  }) async {
    final token = await _idToken();
    if (token == null) {
      throw Exception('auth_required');
    }
    final response = await _client.post(
      _endpoint('/verifyPlayPurchase'),
      headers: _headers(idToken: token),
      body: jsonEncode({
        'purchaseToken': purchaseToken,
        'productId': productId,
        if (orderId != null) 'orderId': orderId,
      }),
    );
    if (response.statusCode == 403) {
      throw PaymentsLimitException();
    }
    if (response.statusCode >= 400) {
      throw Exception('Purchase verification failed (${response.statusCode})');
    }
  }

  Stream<int> completedCoinsTodayStream(String uid) {
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    return _db
        .collection('payments')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .snapshots()
        .map((snapshot) => snapshot.docs.fold<int>(0, (acc, doc) {
              final data = doc.data();
              final coins = data['coins'];
              if (coins is int) {
                return acc + coins;
              }
              if (coins is num) {
                return acc + coins.toInt();
              }
              return acc;
            }));
  }

  static Future<PaymentProvider> resolveProvider({bool? playAvailable}) async {
    final override = kPaymentsProviderEnv.toLowerCase();
    if (override == 'stripe') {
      return PaymentProvider.stripe;
    }
    if (override == 'play') {
      return PaymentProvider.play;
    }

    if (!kIsWeb && Platform.isAndroid) {
      if (playAvailable == true) {
        return PaymentProvider.play;
      }
    }
    return PaymentProvider.stripe;
  }
}

class PaymentsLimitException implements Exception {}
