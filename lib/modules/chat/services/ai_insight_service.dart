import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';
import 'feature_flags.dart';

// Exception used by AI Insight flow.
class AIInsightException implements Exception {
  final String message;
  final int? code; // optional HTTP/status or app-specific code
  final Object? details;
  final bool isNetworkError;
  final bool isTimeout;

  const AIInsightException(
    this.message, {
    this.code,
    this.details,
    this.isNetworkError = false,
    this.isTimeout = false,
  });

  @override
  String toString() => 'AIInsightException(code: $code, message: $message)';
}

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

class OpenAiConfig {
  final String apiKey;
  final String baseUrl;
  final String textModel;
  final Duration timeout;

  const OpenAiConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.textModel,
    required this.timeout,
  });
}

OpenAiConfig loadOpenAiConfig() {
  final key = dotenv.env['OPENAI_API_KEY']?.trim() ?? '';
  final baseEnv = dotenv.env['OPENAI_BASE_URL']?.trim() ?? '';
  final base = baseEnv.isNotEmpty ? baseEnv : 'https://api.openai.com/v1';
  final modelEnv = dotenv.env['OPENAI_MODEL_TEXT']?.trim() ?? '';
  final model = modelEnv.isNotEmpty ? modelEnv : 'gpt-4o-mini';
  return OpenAiConfig(
    apiKey: key,
    baseUrl: base,
    textModel: model,
    timeout: FeatureFlags.aiInsightTimeout,
  );
}

class AiInsightService {
  AiInsightService({OpenAiConfig? config, http.Client? httpClient})
      : _config = config ?? loadOpenAiConfig(),
        _client = httpClient ?? http.Client();

  final OpenAiConfig _config;
  final http.Client _client;

  static bool isConfigured() => (dotenv.env['OPENAI_API_KEY']?.trim() ?? '').isNotEmpty;

  Uri _buildUri(String path) {
    final normalizedBase = _config.baseUrl.endsWith('/')
        ? _config.baseUrl.substring(0, _config.baseUrl.length - 1)
        : _config.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, String> _headers() => <String, String>{
        'Authorization': 'Bearer ${_config.apiKey}',
        'Content-Type': 'application/json',
      };

  Future<OpenAiDiagResult> ping() async {
    final apiKey = _config.apiKey;
    if (apiKey.isEmpty) {
      return OpenAiDiagResult.missingKey();
    }

    final uri = _buildUri('/models');

    try {
      final response = await _client
          .get(uri, headers: _headers())
          .timeout(_config.timeout);

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
    final apiKey = _config.apiKey;
    if (apiKey.isEmpty) {
      throw StateError('OPENAI_API_KEY_MISSING');
    }

    final uri = _buildUri('/chat/completions');
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
      'model': _config.textModel,
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
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(_config.timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final Map<String, dynamic> decoded =
              json.decode(response.body) as Map<String, dynamic>;
          final txt = decoded['choices']?[0]?['message']?['content'] as String? ?? '{}';
          return AiInsight.fromJson(json.decode(txt) as Map<String, dynamic>);
        } catch (err) {
          throw AIInsightException(
            'Invalid AI response format',
            details: err.toString(),
          );
        }
      }
      throw _httpError(response);
    } on TimeoutException {
      throw const AIInsightException(
        'Request timeout',
        isTimeout: true,
      );
    } on SocketException catch (err) {
      throw AIInsightException(
        err.message,
        isNetworkError: true,
        details: err,
      );
    } on http.ClientException catch (err) {
      throw AIInsightException(
        err.message,
        isNetworkError: true,
        details: err,
      );
    } on AIInsightException {
      rethrow;
    } catch (err) {
      throw AIInsightException(
        'Unexpected AI insight error',
        details: err,
      );
    }
  }

  AIInsightException _httpError(http.Response response) {
    final status = response.statusCode;
    final body = response.body.trim();
    if (status == 401 || status == 403) {
      return AIInsightException(
        'Unauthorized OpenAI request',
        code: status,
        details: body,
      );
    }
    if (status == 429) {
      return AIInsightException(
        'Rate limited by OpenAI',
        code: status,
        details: body,
      );
    }
    return AIInsightException(
      'OpenAI request failed',
      code: status,
      details: body,
    );
  }
}
