import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';

class OpenAiDiagResult {
  final bool ok;
  final int? modelsCount;
  final int? status;
  final String? message;

  const OpenAiDiagResult.ok({this.modelsCount})
      : ok = true,
        status = null,
        message = null;

  const OpenAiDiagResult.err({this.status, this.message})
      : ok = false,
        modelsCount = null;

  static OpenAiDiagResult missingKey() =>
      const OpenAiDiagResult.err(status: 0, message: 'Missing API key');

  Map<String, dynamic> toJson() => {
        'ok': ok,
        if (modelsCount != null) 'models': modelsCount,
        if (status != null) 'status': status,
        if (message != null) 'message': message,
      };
}

String get _openAiKey => (dotenv.env['OPENAI_API_KEY'] ?? '').trim();
String get _openAiBaseUrl =>
    (dotenv.env['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1').trim();
String get _openAiModel =>
    (dotenv.env['OPENAI_MODEL_TEXT'] ?? 'gpt-4o-mini').trim();
Duration get _openAiTimeout => Duration(
      milliseconds:
          int.tryParse(dotenv.env['OPENAI_REQUEST_TIMEOUT_MS'] ?? '') ?? 15000,
    );

class AiInsightService {
  AiInsightService({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? timeoutMs,
    http.Client? httpClient,
    Duration? timeout,
  })  : _overrideApiKey = apiKey,
        _overrideBaseUrl = baseUrl,
        _overrideModel = model,
        _overrideTimeout = timeout ??
            (timeoutMs != null
                ? Duration(milliseconds: timeoutMs)
                : null),
        _client = httpClient ?? http.Client();

  final String? _overrideApiKey;
  final String? _overrideBaseUrl;
  final String? _overrideModel;
  final Duration? _overrideTimeout;
  final http.Client _client;

  String get _effectiveApiKey => (_overrideApiKey ?? _openAiKey).trim();
  String get _effectiveBaseUrl => (_overrideBaseUrl ?? _openAiBaseUrl).trim();
  String get _effectiveModel => (_overrideModel ?? _openAiModel).trim();
  Duration get _effectiveTimeout => _overrideTimeout ?? _openAiTimeout;

  bool get isConfigured => _effectiveApiKey.isNotEmpty;

  Future<OpenAiDiagResult> ping() async {
    final apiKey = _effectiveApiKey;
    if (apiKey.isEmpty) {
      return OpenAiDiagResult.missingKey();
    }

    final rawBase = _effectiveBaseUrl.isEmpty
        ? 'https://api.openai.com/v1'
        : _effectiveBaseUrl;
    var base = rawBase.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uriBase = base.endsWith('/v1') ? base : '$base/v1';
    final uri = Uri.parse('$uriBase/models');

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        try {
          final decoded = json.decode(response.body) as Map<String, dynamic>;
          final List<dynamic>? models = decoded['data'] as List<dynamic>?;
          return OpenAiDiagResult.ok(modelsCount: models?.length ?? 0);
        } catch (_) {
          return const OpenAiDiagResult.err(
            status: 200,
            message: 'Unexpected JSON structure',
          );
        }
      }
      return OpenAiDiagResult.err(status: status, message: response.body.trim());
    } on TimeoutException {
      return const OpenAiDiagResult.err(
        status: null,
        message: 'Network timeout',
      );
    } on Object catch (err) {
      return OpenAiDiagResult.err(status: null, message: err.toString());
    }
  }

  Future<AiInsight> analyze({
    required String userLocale,
    String? text,
    String? imageUrl,
    String? followupInstruction,
  }) async {
    final apiKey = _effectiveApiKey;
    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY_MISSING');
    }

    final baseUrl = _effectiveBaseUrl;
    final uri = Uri.parse('$baseUrl/chat/completions');
    final sys =
        'You are an assistant embedded in a chat app. '
        'Given a single message (text and/or image), return a compact JSON object with: '
        '{ "title": string, "bullets": string[], "facts": string[], '
        '"answer": string|null, "translation": string|null, "imageCaption": string|null }. '
        'Write in the user locale: $userLocale. Keep it concise. Output JSON ONLY.';

    final List<Map<String, dynamic>> content = [];
    if (text != null && text.trim().isNotEmpty) {
      content.add({'type': 'text', 'text': text.trim()});
    }
    if (imageUrl != null && imageUrl.isNotEmpty) {
      content.add({
        'type': 'image_url',
        'image_url': {'url': imageUrl},
      });
    }
    if (followupInstruction != null && followupInstruction.isNotEmpty) {
      content.add({'type': 'text', 'text': followupInstruction});
    }

    if (content.isEmpty) {
      return const AiInsight(
        title: 'لا يمكن التحليل',
        bullets: ['هذه الرسالة لا تحتوي على نص أو صورة قابلة للتحليل.'],
      );
    }

    final body = {
      'model': _effectiveModel,
      'temperature': 0.3,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': content},
      ],
    };

    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(_effectiveTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final Map<String, dynamic> decoded = json.decode(response.body) as Map<String, dynamic>;
        final txt = decoded['choices']?[0]?['message']?['content'] as String? ?? '{}';
        return AiInsight.fromJson(json.decode(txt) as Map<String, dynamic>);
      }
    } catch (_) {
      // Swallow exceptions and fall back below.
    }

    return const AiInsight(
      title: 'خدمة الذكاء غير متاحة',
      bullets: ['تعذر الحصول على الملخص حاليًا، حاول لاحقًا.'],
    );
  }
}
