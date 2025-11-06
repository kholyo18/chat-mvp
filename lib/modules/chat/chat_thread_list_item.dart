import 'package:chat_mvp/models/user_profile.dart';
import 'package:chat_mvp/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:characters/characters.dart';

enum ChatThreadMediaType {
  text,
  image,
  video,
  audio,
  file,
  system,
  unknown,
}

class ChatThreadPreviewData {
  const ChatThreadPreviewData({
    required this.type,
    required this.text,
  });

  final ChatThreadMediaType type;
  final String text;

  bool get isAttachment => type != ChatThreadMediaType.text && type != ChatThreadMediaType.system;

  IconData? get icon {
    switch (type) {
      case ChatThreadMediaType.image:
        return Icons.image_rounded;
      case ChatThreadMediaType.video:
        return Icons.videocam_rounded;
      case ChatThreadMediaType.audio:
        return Icons.mic_rounded;
      case ChatThreadMediaType.file:
        return Icons.insert_drive_file_rounded;
      case ChatThreadMediaType.system:
      case ChatThreadMediaType.text:
      case ChatThreadMediaType.unknown:
        return null;
    }
  }
}

String resolveThreadDisplayName({
  required InboxThreadItem thread,
  required String otherUid,
  UserProfile? otherProfile,
}) {
  String? pickFromProfile(UserProfile? profile) {
    if (profile == null) return null;
    final value = profile.displayName.trim();
    if (value.isNotEmpty) {
      return value;
    }
    if (profile.username.trim().isNotEmpty) {
      return '@${profile.username.trim()}';
    }
    return null;
  }

  final profileName = pickFromProfile(otherProfile);
  if (profileName != null) {
    return profileName;
  }

  final rawName = _lookupMemberField(
    thread.raw,
    otherUid,
    containerKeys: const <String>[
      'memberNames',
      'displayNames',
      'names',
      'membersData',
      'profiles',
      'participants',
      'users',
    ],
    fieldCandidates: const <String>['displayName', 'name', 'fullName', 'username', 'title'],
  );
  if (rawName != null) {
    return rawName;
  }

  final username = _lookupMemberField(
    thread.raw,
    otherUid,
    containerKeys: const <String>['usernames', 'profiles', 'membersData'],
    fieldCandidates: const <String>['username', 'handle'],
  );
  if (username != null && username.isNotEmpty) {
    final normalized = username.startsWith('@') ? username : '@$username';
    return normalized;
  }

  return 'مستخدم';
}

String? resolveThreadPhotoUrl({
  required InboxThreadItem thread,
  required String otherUid,
  UserProfile? otherProfile,
}) {
  if (otherProfile != null && otherProfile.photoURL != null && otherProfile.photoURL!.trim().isNotEmpty) {
    return otherProfile.photoURL!.trim();
  }
  return _lookupMemberField(
    thread.raw,
    otherUid,
    containerKeys: const <String>['memberPhotos', 'photos', 'avatars', 'profiles', 'membersData'],
    fieldCandidates: const <String>['photoURL', 'photoUrl', 'avatar', 'avatarUrl', 'image', 'picture'],
  );
}

String? resolveThreadUsername({
  required InboxThreadItem thread,
  required String otherUid,
  UserProfile? otherProfile,
}) {
  if (otherProfile != null && otherProfile.username.trim().isNotEmpty) {
    return otherProfile.username.trim();
  }
  return _lookupMemberField(
    thread.raw,
    otherUid,
    containerKeys: const <String>['usernames', 'membersData', 'profiles'],
    fieldCandidates: const <String>['username', 'handle'],
  );
}

ChatThreadPreviewData resolveThreadPreview(InboxThreadItem thread) {
  final previewText = (thread.lastMessage ?? '').trim();
  final typeString = _resolveLastMessageType(thread.raw);
  final normalized = typeString?.toLowerCase().trim();

  ChatThreadMediaType mapType(String? value) {
    switch (value) {
      case 'text':
      case 'message':
      case 'msg':
        return ChatThreadMediaType.text;
      case 'image':
      case 'photo':
      case 'picture':
      case 'img':
        return ChatThreadMediaType.image;
      case 'video':
      case 'clip':
      case 'media':
        return ChatThreadMediaType.video;
      case 'audio':
      case 'voice':
      case 'voice_note':
      case 'voice-note':
      case 'voiceMessage':
      case 'voice_message':
        return ChatThreadMediaType.audio;
      case 'file':
      case 'document':
      case 'attachment':
        return ChatThreadMediaType.file;
      case 'system':
      case 'info':
      case 'event':
        return ChatThreadMediaType.system;
      default:
        return ChatThreadMediaType.unknown;
    }
  }

  ChatThreadMediaType type = mapType(normalized);
  if (type == ChatThreadMediaType.unknown || type == ChatThreadMediaType.text) {
    final lowered = previewText.toLowerCase();
    if (lowered.contains('📷') || lowered.contains('صورة') || lowered.contains('image') || lowered.contains('photo')) {
      type = ChatThreadMediaType.image;
    } else if (lowered.contains('🎬') || lowered.contains('فيديو') || lowered.contains('video')) {
      type = ChatThreadMediaType.video;
    } else if (lowered.contains('🎙') || lowered.contains('ميكروفون') || lowered.contains('voice') || lowered.contains('audio')) {
      type = ChatThreadMediaType.audio;
    } else if (lowered.contains('📎') || lowered.contains('ملف') || lowered.contains('file') || lowered.contains('document')) {
      type = ChatThreadMediaType.file;
    } else if (normalized == null) {
      type = ChatThreadMediaType.text;
    }
  }

  String text;
  switch (type) {
    case ChatThreadMediaType.image:
      text = 'صورة';
      break;
    case ChatThreadMediaType.video:
      text = 'فيديو';
      break;
    case ChatThreadMediaType.audio:
      text = 'رسالة صوتية';
      break;
    case ChatThreadMediaType.file:
      text = 'ملف';
      break;
    case ChatThreadMediaType.system:
    case ChatThreadMediaType.text:
    case ChatThreadMediaType.unknown:
      text = previewText.isNotEmpty ? previewText : 'ابدأ المحادثة';
      break;
  }

  return ChatThreadPreviewData(type: type, text: text);
}

bool computeThreadHasUnread({
  required InboxThreadItem thread,
  required String currentUid,
  required int unreadCount,
}) {
  if (unreadCount > 0) {
    return true;
  }
  final raw = thread.raw;
  final lastSenderId = raw['lastSenderId'];
  if (lastSenderId is String && lastSenderId.isNotEmpty && lastSenderId != currentUid) {
    final updatedAt = thread.updatedAt?.toDate();
    final seenMap = raw['seen'] ?? raw['seenBy'] ?? raw['reads'] ?? raw['readBy'] ?? raw['lastSeen'] ?? raw['lastRead'];
    final lastSeen = _parseTimestampFromAny(_extractFromMapForUid(seenMap, currentUid));
    if (updatedAt == null) {
      return true;
    }
    if (lastSeen == null || lastSeen.isBefore(updatedAt)) {
      return true;
    }
  }
  return false;
}

String formatChatThreadTimestamp(cf.Timestamp? timestamp, Locale? locale) {
  if (timestamp == null) {
    return '';
  }
  final dt = timestamp.toDate();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final otherDay = DateTime(dt.year, dt.month, dt.day);
  final localeName = locale?.toLanguageTag() ?? 'ar';
  if (today == otherDay) {
    return DateFormat('HH:mm', localeName).format(dt);
  }
  if (otherDay == today.subtract(const Duration(days: 1))) {
    return 'أمس';
  }
  if (today.difference(otherDay).inDays < 7) {
    return DateFormat('EEE', localeName).format(dt);
  }
  return DateFormat('dd/MM/yy', localeName).format(dt);
}

class ChatThreadListItem extends StatelessWidget {
  const ChatThreadListItem({
    super.key,
    required this.threadId,
    required this.displayName,
    required this.preview,
    required this.updatedAt,
    required this.unreadCount,
    required this.hasUnread,
    required this.isLastMessageFromMe,
    this.photoUrl,
    this.isProfileLoading = false,
    this.onTap,
    this.onLongPress,
  });

  final String threadId;
  final String displayName;
  final ChatThreadPreviewData preview;
  final cf.Timestamp? updatedAt;
  final int unreadCount;
  final bool hasUnread;
  final bool isLastMessageFromMe;
  final String? photoUrl;
  final bool isProfileLoading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final formattedTime = formatChatThreadTimestamp(updatedAt, locale);
    final bool showBadge = unreadCount > 0;
    final bool showDot = !showBadge && hasUnread;
    final Color badgeColor = theme.colorScheme.primary;
    final TextStyle titleStyle = theme.textTheme.titleMedium?.copyWith(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(
          fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
          color: theme.colorScheme.onSurface,
          fontSize: 16,
        );
    final Color subtitleColor = hasUnread
        ? theme.colorScheme.onSurface.withOpacity(0.9)
        : theme.textTheme.bodyMedium?.color?.withOpacity(0.7) ?? theme.colorScheme.onSurface.withOpacity(0.65);
    final TextStyle subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
          color: subtitleColor,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ) ??
        TextStyle(
          color: subtitleColor,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
          fontSize: 14,
        );
    final subtitleText = _buildSubtitleText(theme);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                name: displayName,
                photoUrl: photoUrl,
                isLoading: isProfileLoading,
                hasUnread: hasUnread,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                    const SizedBox(height: 4),
                    subtitleText == null
                        ? const SizedBox.shrink()
                        : AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: isProfileLoading ? 0.6 : 1,
                            child: subtitleText,
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formattedTime,
                    style: theme.textTheme.labelSmall?.copyWith(
                          color: hasUnread
                              ? badgeColor
                              : theme.textTheme.labelSmall?.color?.withOpacity(0.7) ?? theme.colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (showBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ) ??
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    )
                  else if (showDot)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSubtitleText(ThemeData theme) {
    final icon = preview.icon;
    String text = preview.text;
    if (isLastMessageFromMe && text.isNotEmpty) {
      text = 'أنت: $text';
    }
    if (icon == null || !preview.isAttachment) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.photoUrl,
    required this.isLoading,
    required this.hasUnread,
  });

  final String name;
  final String? photoUrl;
  final bool isLoading;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final double size = 56;
    final theme = Theme.of(context);
    final bgColor = _avatarColorFor(name, theme);
    final initials = name.isNotEmpty ? name.characters.first : '?';
    final child = photoUrl != null && photoUrl!.isNotEmpty
        ? CircleAvatar(radius: size / 2, backgroundImage: NetworkImage(photoUrl!), backgroundColor: Colors.transparent)
        : CircleAvatar(
            radius: size / 2,
            backgroundColor: bgColor,
            child: Text(
              initials,
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold) ??
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isLoading ? 0.6 : 1,
          child: child,
        ),
        if (hasUnread)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ChatThreadMemberCache {
  ChatThreadMemberCache({cf.FirebaseFirestore? firestore}) : _firestore = firestore ?? cf.FirebaseFirestore.instance;

  final cf.FirebaseFirestore _firestore;
  final Map<String, UserProfile?> _resolved = <String, UserProfile?>{};
  final Map<String, Future<UserProfile?>> _pending = <String, Future<UserProfile?>>{};

  UserProfile? getCached(String uid) => _resolved[uid];

  Future<UserProfile?> fetch(String uid) {
    if (uid.isEmpty) {
      return SynchronousFuture<UserProfile?>(null);
    }
    final cached = _resolved[uid];
    if (cached != null || _resolved.containsKey(uid)) {
      return SynchronousFuture<UserProfile?>(cached);
    }
    final pending = _pending[uid];
    if (pending != null) {
      return pending;
    }
    final future = _load(uid);
    _pending[uid] = future;
    return future;
  }

  Future<UserProfile?> _load(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        final profile = UserProfile.fromJson(data);
        _resolved[uid] = profile;
        return profile;
      }
      _resolved[uid] = null;
      return null;
    } catch (err) {
      debugPrint('ChatThreadMemberCache error for $uid: $err');
      _resolved.putIfAbsent(uid, () => null);
      return null;
    } finally {
      _pending.remove(uid);
    }
  }

  void clear() {
    _resolved.clear();
    _pending.clear();
  }
}

String? _lookupMemberField(
  Map<String, dynamic> raw,
  String otherUid, {
  required List<String> containerKeys,
  required List<String> fieldCandidates,
}) {
  for (final key in containerKeys) {
    final container = raw[key];
    final value = _extractFieldValue(container, otherUid, fieldCandidates);
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

dynamic _extractFromMapForUid(dynamic container, String uid) {
  if (container is Map) {
    if (container.containsKey(uid)) {
      return container[uid];
    }
    for (final entry in container.entries) {
      final key = entry.key?.toString() ?? '';
      if (key.endsWith(uid)) {
        return entry.value;
      }
      if (entry.value is Map) {
        final nested = entry.value as Map;
        if ((nested['uid'] ?? nested['id'])?.toString() == uid) {
          return nested;
        }
      }
    }
  }
  if (container is Iterable) {
    for (final item in container) {
      if (item is Map) {
        final map = item;
        final id = (map['uid'] ?? map['id'])?.toString();
        if (id == uid) {
          return map;
        }
      }
    }
  }
  return null;
}

String? _extractFieldValue(dynamic container, String otherUid, List<String> fieldCandidates) {
  final target = _extractFromMapForUid(container, otherUid);
  if (target == null) {
    if (container is Map) {
      for (final value in container.values) {
        final resolved = _normalizeValue(value, fieldCandidates);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    if (container is Iterable) {
      for (final value in container) {
        final resolved = _normalizeValue(value, fieldCandidates);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    return null;
  }
  return _normalizeValue(target, fieldCandidates);
}

String? _normalizeValue(dynamic raw, List<String> fieldCandidates) {
  if (raw is String) {
    return raw.trim();
  }
  if (raw is Map) {
    for (final key in fieldCandidates) {
      final value = raw[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return null;
}

String? _resolveLastMessageType(Map<String, dynamic> raw) {
  const directKeys = <String>[
    'lastMessageType',
    'last_message_type',
    'lastType',
    'last_message_kind',
    'lastMessageKind',
    'lastMessageMediaType',
    'lastMessageCategory',
    'lastMessagePayloadType',
    'lastMessageContentType',
  ];
  for (final key in directKeys) {
    final value = raw[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  const nestedKeys = <String>[
    'lastMessageMeta',
    'lastMessageMetadata',
    'lastMessageInfo',
    'lastMessageData',
  ];
  for (final key in nestedKeys) {
    final nested = raw[key];
    if (nested is Map) {
      final value = _normalizeValue(nested, const <String>['type', 'kind', 'category', 'mediaType', 'contentType']);
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return null;
}

DateTime? _parseTimestampFromAny(dynamic raw) {
  if (raw == null) return null;
  if (raw is cf.Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  if (raw is double) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  if (raw is Map) {
    final fromFieldsValue = raw['seconds'];
    if (fromFieldsValue is int) {
      final nanoseconds = raw['nanoseconds'];
      final millis = fromFieldsValue * 1000 + (nanoseconds is int ? nanoseconds ~/ 1000000 : 0);
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    for (final value in raw.values) {
      final parsed = _parseTimestampFromAny(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

Color _avatarColorFor(String name, ThemeData theme) {
  final palette = <Color>[
    const Color(0xFF80CBC4),
    const Color(0xFFA5D6A7),
    const Color(0xFF4DB6AC),
    const Color(0xFF81C784),
    const Color(0xFF26A69A),
    const Color(0xFF66BB6A),
  ];
  final hash = name.codeUnits.fold<int>(0, (acc, code) => acc + code);
  return palette[hash.abs() % palette.length];
}
