class FeatureFlags {
  const FeatureFlags();

  static const bool aiInsightEnabled = true;
  static const bool aiInsightRequirePremium = true;
  static const Duration aiInsightTimeout = Duration(seconds: 15);
}
