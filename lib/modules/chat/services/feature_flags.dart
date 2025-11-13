class FeatureFlags {
  const FeatureFlags._();

  static const bool enableAiSwipeInsight = bool.fromEnvironment(
    'FEATURE_AI_SWIPE_INSIGHT',
    defaultValue: false,
  );
}
