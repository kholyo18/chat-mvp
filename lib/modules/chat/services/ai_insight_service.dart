import '../models/ai_insight.dart';
import 'ai_insight_provider.dart';

class AiInsightService {
  AiInsightService({AiInsightProvider? provider})
      : _provider = provider ?? buildAiInsightProvider();

  final AiInsightProvider _provider;

  Future<AiInsight> getInsightFor(String text) {
    return _provider.analyze(text);
  }
}
