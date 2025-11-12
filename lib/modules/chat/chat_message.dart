import 'package:cloud_firestore/cloud_firestore.dart' as cf;

enum ChatMessageType {
  text,
  image,
  video,
  audio,
  file,
  system,
}

extension ChatMessageTypeParser on ChatMessageType {
  String get value {
    switch (this) {
      case ChatMessageType.text:
        return 'text';
      case ChatMessageType.image:
        return 'image';
      case ChatMessageType.video:
        return 'video';
      case ChatMessageType.audio:
        return 'audio';
      case ChatMessageType.file:
        return 'file';
      case ChatMessageType.system:
        return 'system';
    }
  }

  static ChatMessageType fromValue(String? raw) {
    switch (raw) {
      case 'image':
        return ChatMessageType.image;
      case 'video':
        return ChatMessageType.video;
      case 'audio':
        return ChatMessageType.audio;
      case 'file':
        return ChatMessageType.file;
      case 'system':
        return ChatMessageType.system;
      case 'text':
      default:
        return ChatMessageType.text;
    }
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.sentAt,
    this.deliveredAt,
    this.seenAt,
    this.text,
    this.mediaUrl,
    this.mediaThumbUrl,
    this.replyToMessageId,
    this.forwardFromThreadId,
    this.status,
    this.deletedFor,
    this.deletedForEveryone = false,
    this.metadata,
    this.reference,
  });

  factory ChatMessage.fromSnapshot(
    cf.QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return ChatMessage.fromMap(
      data,
      id: doc.id,
      reference: doc.reference,
    );
  }

  factory ChatMessage.fromMap(
    Map<String, dynamic> data, {
    required String id,
    cf.DocumentReference<Map<String, dynamic>>? reference,
  }) {
    return ChatMessage(
      id: id,
      senderId: (data['senderId'] as String?) ?? (data['from'] as String?),
      type: ChatMessageTypeParser.fromValue(data['type'] as String?),
      text: (data['text'] as String?)?.trim(),
      mediaUrl: data['mediaUrl'] as String?,
      mediaThumbUrl: data['mediaThumbUrl'] as String?,
      replyToMessageId: data['replyToMessageId'] as String?,
      forwardFromThreadId: data['forwardedFromThreadId'] as String?,
      status: data['status'] as String?,
      deletedForEveryone: data['deletedForEveryone'] == true,
      deletedFor: data['deletedFor'] is Iterable
          ? List<String>.from((data['deletedFor'] as Iterable).whereType<String>())
          : const <String>[],
      metadata: data['metadata'] is Map
          ? Map<String, dynamic>.from(
              (data['metadata'] as Map<dynamic, dynamic>).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : const <String, dynamic>{},
      createdAt: _parseTimestamp(data['createdAt']),
      sentAt: _parseTimestamp(data['sentAt']),
      deliveredAt: _parseTimestamp(data['deliveredAt']),
      seenAt: _parseTimestamp(data['seenAt']),
      reference: reference,
    );
  }

  Map<String, Object?> toFirestore() {
    return <String, Object?>{
      'from': senderId,
      'senderId': senderId,
      'type': type.value,
      'text': text,
      'mediaUrl': mediaUrl,
      'mediaThumbUrl': mediaThumbUrl,
      'replyToMessageId': replyToMessageId,
      'forwardedFromThreadId': forwardFromThreadId,
      'status': status,
      'deletedFor': deletedFor,
      'deletedForEveryone': deletedForEveryone,
      'metadata': metadata,
      'createdAt': createdAt,
      'sentAt': sentAt,
      'deliveredAt': deliveredAt,
      'seenAt': seenAt,
    }..removeWhere((_, value) => value == null);
  }

  final String id;
  final String? senderId;
  final ChatMessageType type;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? seenAt;
  final String? text;
  final String? mediaUrl;
  final String? mediaThumbUrl;
  final String? replyToMessageId;
  final String? forwardFromThreadId;
  final String? status;
  final List<String>? deletedFor;
  final bool deletedForEveryone;
  final Map<String, dynamic>? metadata;
  final cf.DocumentReference<Map<String, dynamic>>? reference;

  bool isHiddenFor(String uid) {
    if (deletedForEveryone) {
      return false;
    }
    final list = deletedFor;
    if (list == null) {
      return false;
    }
    return list.contains(uid);
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is cf.Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true).toLocal();
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
