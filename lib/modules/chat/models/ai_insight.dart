import 'package:cloud_firestore/cloud_firestore.dart' as cf;

class AiInsight {
  const AiInsight({
    required this.entity,
    required this.type,
    required this.bullets,
    required this.facts,
    required this.locale,
  });

  factory AiInsight.fromMap(Map<String, dynamic> data) {
    final rawFacts = data['facts'];
    final facts = <String, String>{};
    if (rawFacts is Map) {
      rawFacts.forEach((key, value) {
        final normalizedKey = key == null ? null : key.toString();
        final normalizedValue = value == null ? null : value.toString();
        if (normalizedKey != null && normalizedKey.isNotEmpty &&
            normalizedValue != null && normalizedValue.isNotEmpty) {
          facts[normalizedKey] = normalizedValue;
        }
      });
    }
    return AiInsight(
      entity: (data['entity'] as String?)?.trim() ?? '',
      type: (data['type'] as String?)?.trim() ?? 'other',
      bullets: data['summary_bullets'] is Iterable
          ? data['summary_bullets']
              .map((e) => e.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList()
          : data['bullets'] is Iterable
              ? data['bullets']
                  .map((e) => e.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toList()
              : const <String>[],
      facts: facts,
      locale: (data['locale'] as String?)?.trim() ?? 'ar',
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'entity': entity,
      'type': type,
      'summary_bullets': bullets,
      'facts': facts,
      'locale': locale,
      'createdAt': cf.FieldValue.serverTimestamp(),
    };
  }

  final String entity;
  final String type; // place|person|org|other
  final List<String> bullets;
  final Map<String, String> facts;
  final String locale;

  bool get hasContent => entity.isNotEmpty && (bullets.isNotEmpty || facts.isNotEmpty);
}
