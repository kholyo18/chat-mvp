import 'package:cloud_firestore/cloud_firestore.dart' as cf;

/// Immutable representation of a user's public profile data.
///
/// The model keeps the shape in sync with the Firestore document stored
/// under `users/{uid}`. Use [fromJson] / [toJson] to convert between the
/// in-memory representation and Firestore maps.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.username,
    this.bio,
    this.website,
    this.location,
    this.birthdate,
    this.photoURL,
    this.coverURL,
    this.showEmail = false,
    this.dmPermission = 'all',
    this.updatedAt,
  });

  final String displayName;
  final String username;
  final String? bio;
  final String? website;
  final String? location;
  final DateTime? birthdate;
  final String? photoURL;
  final String? coverURL;
  final bool showEmail;
  final String dmPermission;
  final DateTime? updatedAt;

  /// Creates a profile instance from Firestore data.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> privacy =
        (json['privacy'] as Map<String, dynamic>?) ?? defaultPrivacy();

    DateTime? parseTimestamp(dynamic raw) {
      if (raw is cf.Timestamp) return raw.toDate();
      if (raw is DateTime) return raw;
      if (raw is num) {
        return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
      }
      if (raw is String) {
        return DateTime.tryParse(raw);
      }
      return null;
    }

    String? readString(dynamic raw) {
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
      return null;
    }

    return UserProfile(
      displayName: (json['displayName'] as String?)?.trim() ?? '',
      username: (json['username'] as String?)?.trim() ?? '',
      bio: readString(json['bio']),
      website: readString(json['website']),
      location: readString(json['location']),
      birthdate: parseTimestamp(json['birthdate']),
      photoURL: readString(json['photoURL'] ?? json['photoUrl']),
      coverURL: readString(json['coverURL'] ?? json['coverUrl']),
      showEmail: privacy['showEmail'] == true,
      dmPermission:
          (privacy['dmPermission'] as String?) == 'followers' ? 'followers' : 'all',
      updatedAt: parseTimestamp(json['updatedAt']),
    );
  }

  /// Serialises the profile for Firestore writes.
  Map<String, dynamic> toJson({bool includeNulls = false}) {
    Map<String, dynamic> filter(Map<String, dynamic> source) {
      if (includeNulls) return source;
      source.removeWhere((key, value) => value == null);
      return source;
    }

    return filter({
      'displayName': displayName,
      'username': username,
      'bio': bio?.trim().isEmpty ?? true ? null : bio?.trim(),
      'website': website?.trim().isEmpty ?? true ? null : website?.trim(),
      'location': location?.trim().isEmpty ?? true ? null : location?.trim(),
      'birthdate': birthdate != null ? cf.Timestamp.fromDate(birthdate!) : null,
      'photoURL': photoURL,
      'coverURL': coverURL,
      'privacy': {
        'showEmail': showEmail,
        'dmPermission': dmPermission,
      },
      if (updatedAt != null) 'updatedAt': cf.Timestamp.fromDate(updatedAt!),
    });
  }

  UserProfile copyWith({
    String? displayName,
    String? username,
    String? bio,
    String? website,
    String? location,
    DateTime? birthdate,
    String? photoURL,
    String? coverURL,
    bool? showEmail,
    String? dmPermission,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      website: website ?? this.website,
      location: location ?? this.location,
      birthdate: birthdate ?? this.birthdate,
      photoURL: photoURL ?? this.photoURL,
      coverURL: coverURL ?? this.coverURL,
      showEmail: showEmail ?? this.showEmail,
      dmPermission: dmPermission ?? this.dmPermission,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Validates a username. Returns `null` when valid, otherwise an error key.
  static String? validateUsername(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'username_required';
    }
    final regex = RegExp(r'^[a-z0-9_]{3,20}$');
    if (!regex.hasMatch(trimmed)) {
      return 'username_invalid';
    }
    return null;
  }

  /// Normalises a website URL. Returns an empty string if [value] is empty.
  ///
  /// Throws a [FormatException] with key `invalid_website` when the URL cannot
  /// be normalised to a valid http(s) address.
  static String sanitizeWebsite(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final normalised = trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.tryParse(normalised);
    final bool validScheme = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!validScheme || uri!.host.isEmpty) {
      throw const FormatException('invalid_website');
    }
    return uri.toString();
  }
}

/// Default privacy values for newly created profiles.
Map<String, dynamic> defaultPrivacy() => const {
      'showEmail': false,
      'dmPermission': 'all',
    };
