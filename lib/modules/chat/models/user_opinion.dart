import 'package:cloud_firestore/cloud_firestore.dart';

class UserOpinion {
  const UserOpinion({
    required this.relationshipType,
    required this.perception,
    required this.likedThings,
    required this.personalityTraits,
    required this.admirationPercent,
    required this.createdAt,
    required this.updatedAt,
  });

  final String relationshipType;
  final String perception;
  final List<String> likedThings;
  final List<String> personalityTraits;
  final int admirationPercent;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory UserOpinion.fromMap(Map<String, dynamic> map) {
    return UserOpinion(
      relationshipType: (map['relationshipType'] as String?) ?? 'none',
      perception: (map['perception'] as String?) ?? 'none',
      likedThings: _parseStringList(map['likedThings']),
      personalityTraits: _parseStringList(map['personalityTraits']),
      admirationPercent: (map['admirationPercent'] as num?)?.round() ?? 0,
      createdAt:
          _parseDate(map['createdAt']) ?? _parseDate(map['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDate(map['updatedAt']) ??
          _parseDate(map['updated_at']) ??
          _parseDate(map['lastUpdated']) ??
          DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'relationshipType': relationshipType,
      'perception': perception,
      'likedThings': likedThings,
      'personalityTraits': personalityTraits,
      'admirationPercent': admirationPercent,
      'createdAt': Timestamp.fromDate(createdAt.toUtc()),
      'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
      'lastUpdated': Timestamp.fromDate(updatedAt.toUtc()),
    };
  }

  UserOpinion copyWith({
    String? relationshipType,
    String? perception,
    List<String>? likedThings,
    List<String>? personalityTraits,
    int? admirationPercent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserOpinion(
      relationshipType: relationshipType ?? this.relationshipType,
      perception: perception ?? this.perception,
      likedThings: likedThings ?? this.likedThings,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      admirationPercent: admirationPercent ?? this.admirationPercent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is Iterable) {
      return raw.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toUtc();
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toUtc();
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toUtc();
    }
    if (raw is double) {
      return DateTime.fromMillisecondsSinceEpoch(raw.round(), isUtc: true).toUtc();
    }
    return null;
  }
}
