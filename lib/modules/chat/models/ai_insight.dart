class AiInsight {
  final String title;
  final String summary;
  final Map<String, String> facts;

  const AiInsight({
    required this.title,
    required this.summary,
    this.facts = const <String, String>{},
  });
}
