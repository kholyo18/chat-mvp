import 'package:cloud_firestore/cloud_firestore.dart' as cf;

DateTime? _parseTimestamp(dynamic raw) {
  if (raw is cf.Timestamp) {
    return raw.toDate();
  }
  if (raw is DateTime) {
    return raw;
  }
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      raw.toInt(),
      isUtc: true,
    ).toLocal();
  }
  if (raw is String) {
    return DateTime.tryParse(raw)?.toLocal();
  }
  return null;
}

/// Immutable representation of a user's live typing preview state.
class TypingPreview {
  const TypingPreview({
    required this.conversationId,
    required this.userId,
    required this.text,
    required this.updatedAt,
  });

  final String conversationId;
  final String userId;
  final String text;
  final DateTime? updatedAt;

  bool get isEmpty => text.trim().isEmpty;

  factory TypingPreview.fromSnapshot(
    cf.DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final conversationRef = snapshot.reference.parent.parent;
    final conversationId = conversationRef?.id ?? '';
    final text = (data['text'] as String?) ?? '';
    return TypingPreview(
      conversationId: conversationId,
      userId: snapshot.id,
      text: text,
      updatedAt: _parseTimestamp(data['updatedAt']),
    );
  }
}

/// UI-facing view state for banner rendering.
class TypingPreviewState {
  const TypingPreviewState({
    required this.preview,
    required this.rawPreview,
    required this.canViewPreview,
  });

  /// Preview text that is safe to show to the viewer. This will be `null`
  /// whenever the viewer is not entitled to see the preview contents.
  final TypingPreview? preview;

  /// Raw preview snapshot (if any) irrespective of the viewer entitlement.
  final TypingPreview? rawPreview;

  /// Whether the current viewer can see live previews.
  final bool canViewPreview;

  bool get hasViewablePreview => canViewPreview && (preview?.isEmpty == false);

  String? get viewableText => canViewPreview ? preview?.text.trim() : null;
}
