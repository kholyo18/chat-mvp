import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';

class AiInsightService {
  AiInsightService({
    String? apiKey,
    String? baseUrl,
    String? model,
    int? timeoutMs,
    http.Client? httpClient,
  })  : apiKey = apiKey ??
            const String.fromEnvironment('OPENAI_API_KEY', defaultValue: ''),
        baseUrl = baseUrl ??
            const String.fromEnvironment(
              'OPENAI_BASE_URL',
              defaultValue: 'https://api.openai.com/v1',
            ),
        model = model ??
            const String.fromEnvironment(
              'OPENAI_MODEL_TEXT',
              defaultValue: 'gpt-4o-mini',
            ),
        timeoutMs = timeoutMs ?? _readTimeoutFromEnv(),
        _client = httpClient ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final int timeoutMs;
  final http.Client _client;

  bool get isConfigured => apiKey.isNotEmpty;

  Future<AiInsight> analyze({
    required String userLocale,
    String? text,
    String? imageUrl,
    String? followupInstruction,
  }) async {
    if (!isConfigured) {
      return const AiInsight(
        title: 'الميزة غير مفعّلة',
        bullets: ['مطلوب مفتاح OpenAI لتفعيل الملخص الذكي.'],
      );
    }

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
      'model': model,
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
          .timeout(Duration(milliseconds: timeoutMs));

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

  static int _readTimeoutFromEnv() {
    const raw = String.fromEnvironment('OPENAI_REQUEST_TIMEOUT_MS', defaultValue: '15000');
    return int.tryParse(raw) ?? 15000;
  }
}
