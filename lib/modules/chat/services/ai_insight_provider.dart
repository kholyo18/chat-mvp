import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_insight.dart';

abstract class AiInsightProvider {
  Future<AiInsight> analyze(String text);
}

class MockAiInsightProvider implements AiInsightProvider {
  @override
  Future<AiInsight> analyze(String text) async {
    final t = text.trim();
    return AiInsight(
      title: t.isEmpty ? 'Insight' : t,
      summary: 'Smart summary about “$t”. Replace via HTTP provider when endpoint is set.',
      facts: const <String, String>{'Source': 'Mock'},
    );
  }
}

class HttpAiInsightProvider implements AiInsightProvider {
  HttpAiInsightProvider(this.endpoint);

  final String endpoint;

  @override
  Future<AiInsight> analyze(String text) async {
    try {
      final uri = Uri.parse(endpoint);
      final response = await http.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, Object?>{'text': text}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('AI insight request failed (${response.statusCode})');
      }
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('AI insight response malformed');
      }
      final title = (decoded['title'] as String?)?.trim();
      final summary = (decoded['summary'] as String?)?.trim();
      if (title == null || title.isEmpty || summary == null || summary.isEmpty) {
        throw Exception('AI insight response missing fields');
      }
      final Map<String, String> facts = <String, String>{};
      final rawFacts = decoded['facts'];
      if (rawFacts is Map) {
        rawFacts.forEach((key, value) {
          final factKey = key?.toString();
          final factValue = value?.toString();
          if (factKey != null && factValue != null) {
            facts[factKey] = factValue;
          }
        });
      }
      return AiInsight(title: title, summary: summary, facts: facts);
    } catch (error) {
      throw Exception('Failed to fetch AI insight: $error');
    }
  }
}

AiInsightProvider buildAiInsightProvider() {
  const endpoint = String.fromEnvironment('AI_INSIGHT_ENDPOINT', defaultValue: '');
  if (endpoint.isNotEmpty) {
    return HttpAiInsightProvider(endpoint);
  }
  return MockAiInsightProvider();
}
