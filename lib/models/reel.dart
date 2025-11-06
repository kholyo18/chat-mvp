/// Model representing a short vertical video reel in the app.
import 'package:cloud_firestore/cloud_firestore.dart';

class Reel {
  const Reel({
    required this.id,
    required this.userId,
    required this.videoUrl,
    required this.caption,
    required this.likesCount,
    required this.commentsCount,
    required this.createdAt,
    required this.isPublic,
    this.likes = const <String>[],
  });

  final String id;
  final String userId;
  final String videoUrl;
  final String caption;
  final int likesCount;
  final int commentsCount;
  final DateTime createdAt;
  final bool isPublic;
  final List<String> likes;

  factory Reel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final createdAtRaw = data['createdAt'];
    DateTime createdAt = DateTime.now();
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    } else if (createdAtRaw is num) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtRaw.toInt());
    } else if (createdAtRaw is String) {
      final parsed = DateTime.tryParse(createdAtRaw);
      if (parsed != null) {
        createdAt = parsed;
      }
    }

    final List<dynamic>? likesRaw = data['likes'] as List<dynamic>?;
    final likes = likesRaw != null
        ? likesRaw.whereType<String>().toList(growable: false)
        : const <String>[];

    return Reel(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      videoUrl: (data['videoUrl'] as String?) ?? '',
      caption: (data['caption'] as String?) ?? '',
      likesCount: (data['likesCount'] as int?) ?? likes.length,
      commentsCount: (data['commentsCount'] as int?) ?? 0,
      createdAt: createdAt,
      isPublic: (data['isPublic'] as bool?) ?? true,
      likes: likes,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'userId': userId,
      'videoUrl': videoUrl,
      'caption': caption,
      'likesCount': likesCount,
      'commentsCount': commentsCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'isPublic': isPublic,
      'likes': likes,
    };
  }

  Reel copyWith({
    int? likesCount,
    int? commentsCount,
    List<String>? likes,
  }) {
    return Reel(
      id: id,
      userId: userId,
      videoUrl: videoUrl,
      caption: caption,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      createdAt: createdAt,
      isPublic: isPublic,
      likes: likes ?? this.likes,
    );
  }
}
