import 'package:cloud_firestore/cloud_firestore.dart' as cf;

const Set<String> _kKnownVipTiers = <String>{
  'none',
  'bronze',
  'silver',
  'gold',
  'platinum',
};

String _normaliseVipTier(String? value) {
  final lower = (value ?? '').trim().toLowerCase();
  if (_kKnownVipTiers.contains(lower)) {
    return lower;
  }
  if (lower == 'basic') {
    return 'none';
  }
  return 'none';
}

/// Representation of the VIP membership state for a user.
class VipStatus {
  const VipStatus({
    required this.tier,
    this.expiresAt,
  });

  final String tier;
  final DateTime? expiresAt;

  bool get isActive => expiresAt == null || expiresAt!.isAfter(DateTime.now());

  VipStatus copyWith({
    String? tier,
    DateTime? expiresAt,
  }) {
    return VipStatus(
      tier: tier ?? this.tier,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  static VipStatus fromRaw(
    dynamic rawVip, {
    String? fallbackTier,
    DateTime? fallbackExpiry,
  }) {
    String tier = _normaliseVipTier(fallbackTier);
    DateTime? expiresAt = fallbackExpiry;

    if (rawVip is Map<String, dynamic>) {
      tier = _normaliseVipTier(rawVip['tier'] as String? ?? tier);
      final rawExpires = rawVip['expiresAt'];
      if (rawExpires is cf.Timestamp) {
        expiresAt = rawExpires.toDate();
      } else if (rawExpires is DateTime) {
        expiresAt = rawExpires;
      } else if (rawExpires is num) {
        expiresAt =
            DateTime.fromMillisecondsSinceEpoch(rawExpires.toInt(), isUtc: true)
                .toLocal();
      } else if (rawExpires is String) {
        expiresAt = DateTime.tryParse(rawExpires);
      }
    } else if (rawVip is String) {
      tier = _normaliseVipTier(rawVip);
    }

    if (expiresAt != null && expiresAt.isUtc) {
      expiresAt = expiresAt.toLocal();
    }

    return VipStatus(
      tier: tier,
      expiresAt: expiresAt,
    );
  }
}

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
    this.verified = false,
    this.vip = const VipStatus(tier: 'none'),
    this.coins = 0,
    this.badges = const <String>[],
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
  final bool verified;
  final VipStatus vip;
  final int coins;
  final List<String> badges;

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

    int readInt(dynamic raw, [int fallback = 0]) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    DateTime? parseVipExpiry(Map<String, dynamic> json) {
      final vipRaw = json['vip'];
      if (vipRaw is Map<String, dynamic>) {
        final value = vipRaw['expiresAt'];
        return parseTimestamp(value);
      }
      final fallback = json['vipExpiresAt'];
      return parseTimestamp(fallback);
    }

    final fallbackVipTier = readString(json['vipTier']) ?? readString(json['vipLevel']);

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
      verified: json['verified'] == true,
      vip: VipStatus.fromRaw(
        json['vip'],
        fallbackTier: fallbackVipTier,
        fallbackExpiry: parseVipExpiry(json),
      ),
      coins: readInt(json['coins']),
      badges: (json['badges'] is Iterable)
          ? List<String>.from(
              (json['badges'] as Iterable)
                  .whereType<String>()
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty),
            )
          : const <String>[],
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
      // The following fields are server-managed and intentionally omitted from
      // client writes: coins, vip, verified, badges.
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
    bool? verified,
    VipStatus? vip,
    int? coins,
    List<String>? badges,
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
      verified: verified ?? this.verified,
      vip: vip ?? this.vip,
      coins: coins ?? this.coins,
      badges: badges ?? this.badges,
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
