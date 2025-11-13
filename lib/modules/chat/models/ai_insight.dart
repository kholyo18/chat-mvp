class AiInsight {
  final String title;
  final List<String> bullets;
  final List<String> facts;
  final String? answer;
  final String? translation;
  final String? imageCaption;

  const AiInsight({
    required this.title,
    required this.bullets,
    this.facts = const [],
    this.answer,
    this.translation,
    this.imageCaption,
  });

  factory AiInsight.fromJson(Map<String, dynamic> j) => AiInsight(
        title: j['title'] as String? ?? 'AI insight',
        bullets: (j['bullets'] as List?)?.cast<String>() ?? const [],
        facts: (j['facts'] as List?)?.cast<String>() ?? const [],
        answer: j['answer'] as String?,
        translation: j['translation'] as String?,
        imageCaption: j['imageCaption'] as String?,
      );
}
