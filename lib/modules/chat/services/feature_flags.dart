import 'package:flutter_dotenv/flutter_dotenv.dart';

class FeatureFlags {
  const FeatureFlags();

  bool get enableAiSwipeInsight => canUseSwipeAiInsight;

  static bool get canUseSwipeAiInsight {
    final k = (dotenv.env['OPENAI_API_KEY'] ?? '').trim();
    return k.isNotEmpty;
  }
}
