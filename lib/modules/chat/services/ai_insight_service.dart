import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';

const String _aiApiBase = String.fromEnvironment('AI_API_BASE', defaultValue: '');
const String _aiApiKey = String.fromEnvironment('AI_API_KEY', defaultValue: '');
const Duration _aiCacheTtl = Duration(days: 7);
const int _aiMemoryCacheLimit = 50;
const Duration _aiRequestTimeout = Duration(seconds: 6);
const String _aiPrompt =
    'Extract the main entity or topic from the user message, then return a concise 4-6 bullet summary and 3-6 fast facts. Respond as JSON with keys: entity, type, summary_bullets[], facts{key:value}, locale.';

class AiInsightService {
  AiInsightService._internal({
    cf.FirebaseFirestore? firestore,
    AiProvider? provider,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _provider = provider ?? _buildDefaultProvider();

  static final AiInsightService instance = AiInsightService._internal();

  final cf.FirebaseFirestore _firestore;
  final AiProvider? _provider;
  final LinkedHashMap<String, AiInsight> _memoryCache =
      LinkedHashMap<String, AiInsight>();

  Future<AiInsight?> getInsight({
    required String threadId,
    required String messageId,
    required String text,
    String? locale,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return null;
    }
    final cacheKey = _cacheKey(threadId, messageId);
    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final firestoreCached = await _readFromFirestore(threadId, messageId);
    if (firestoreCached != null) {
      _remember(cacheKey, firestoreCached);
      return firestoreCached;
    }

    final provider = _provider;
    if (provider == null) {
      return null;
    }

    try {
      final insight = await provider
          .fetchInsight(text: normalizedText, locale: locale ?? 'ar')
          .timeout(_aiRequestTimeout);
      if (insight != null && insight.hasContent) {
        _remember(cacheKey, insight);
        await _writeToFirestore(threadId, messageId, insight);
        return insight;
      }
    } on TimeoutException catch (error, stackTrace) {
      log('AiInsight error: $error', stackTrace: stackTrace);
    } catch (error, stackTrace) {
      log('AiInsight error: $error', stackTrace: stackTrace);
    }
    return null;
  }

  Future<AiInsight?> _readFromFirestore(String threadId, String messageId) async {
    try {
      final docRef = _insightDoc(threadId, messageId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      final createdAt = data['createdAt'];
      DateTime? created;
      if (createdAt is cf.Timestamp) {
        created = createdAt.toDate();
      } else if (createdAt is DateTime) {
        created = createdAt;
      }
      if (created != null) {
        final age = DateTime.now().difference(created);
        if (age > _aiCacheTtl) {
          return null;
        }
      }
      return AiInsight.fromMap(data);
    } catch (error, stackTrace) {
      log('AiInsight error: $error', stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _writeToFirestore(
    String threadId,
    String messageId,
    AiInsight insight,
  ) async {
    try {
      final docRef = _insightDoc(threadId, messageId);
      await docRef.set(insight.toMap(), cf.SetOptions(merge: true));
    } catch (error, stackTrace) {
      log('AiInsight error: $error', stackTrace: stackTrace);
    }
  }

  cf.DocumentReference<Map<String, dynamic>> _insightDoc(
    String threadId,
    String messageId,
  ) {
    return _firestore
        .collection('ai_insights')
        .doc(threadId)
        .collection('messages')
        .doc(messageId);
  }

  void _remember(String key, AiInsight value) {
    _memoryCache.remove(key);
    _memoryCache[key] = value;
    if (_memoryCache.length > _aiMemoryCacheLimit) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  String _cacheKey(String threadId, String messageId) => '$threadId::$messageId';

  static AiProvider? _buildDefaultProvider() {
    if (_aiApiBase.isEmpty) {
      return null;
    }
    return OpenAiProvider(
      endpoint: _aiApiBase,
      apiKey: _aiApiKey,
      client: http.Client(),
    );
  }
}

abstract class AiProvider {
  Future<AiInsight?> fetchInsight({
    required String text,
    required String locale,
  });
}

class OpenAiProvider implements AiProvider {
  OpenAiProvider({
    required String endpoint,
    required String apiKey,
    http.Client? client,
  })  : _endpoint = endpoint,
        _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _endpoint;
  final String _apiKey;
  final http.Client _client;

  @override
  Future<AiInsight?> fetchInsight({
    required String text,
    required String locale,
  }) async {
    final uri = Uri.parse(_endpoint);
    final payload = <String, dynamic>{
      'prompt': _aiPrompt,
      'text': text,
      'locale': locale,
    };
    final response = await _client.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return AiInsight.fromMap(decoded);
      }
      if (decoded is Map) {
        return AiInsight.fromMap(Map<String, dynamic>.from(decoded));
      }
      return null;
    }
    throw AiInsightException(
        'AI provider failed (${response.statusCode}): ${response.body}');
  }
}

class AiInsightException implements Exception {
  AiInsightException(this.message);

  final String message;

  @override
  String toString() => message;
}
