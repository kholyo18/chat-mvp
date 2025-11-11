import 'dart:async';

import 'package:characters/characters.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../models/user_profile.dart';
import '../models/typing_preview.dart';

const _kMaxPreviewLength = 500;
const _kPreviewThrottle = Duration(milliseconds: 275);

class TypingPreviewService {
  TypingPreviewService({cf.FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? cf.FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final cf.FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _privacySub;

  final Map<String, _PendingPreview> _pending = <String, _PendingPreview>{};
  final Set<String> _activeConversations = <String>{};
  final StreamController<bool> _viewAccessController =
      StreamController<bool>.broadcast();

  String? _currentUid;
  bool _viewerHasPreviewAccess = false;
  bool _shareTypingPreview = false;
  bool _canSwipeDelete = false;

  bool get _canSend => _shareTypingPreview;
  bool get _canView => _viewerHasPreviewAccess;

  bool get canSendPreview => _currentUid != null && _canSend;
  bool get canViewPreview => _canView;

  /// Premium entitlements for features such as the swipe-to-delete action
  /// reuse the same billing flags that gate typing previews.
  bool get canUseSwipePermanentDelete => _canSwipeDelete;

  Future<void> initialize() async {
    await _handleAuth(_auth.currentUser);
    await _authSub?.cancel();
    _authSub = _auth.userChanges().listen(
      _handleAuth,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('TypingPreviewService auth listen error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
    );
  }

  Future<void> _handleAuth(User? user) async {
    _currentUid = user?.uid;
    _viewerHasPreviewAccess = false;
    _shareTypingPreview = false;
    _activeConversations.clear();
    await _userSub?.cancel();
    await _privacySub?.cancel();
    if (user == null) {
      return;
    }
    _listenToUserDoc(user.uid);
    _listenToPrivacyDoc(user.uid);
  }

  void _listenToUserDoc(String uid) {
    _userSub?.cancel();
    _userSub = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) {
              _updateViewerAccess(false);
              _updateSwipeDeleteAccess(false);
              return;
            }
            // TODO(typing-preview): Replace VIP tier check with billing entitlements when available.
            final vipStatus = VipStatus.fromRaw(
              data['vip'],
              fallbackTier:
                  (data['vipTier'] as String?) ?? (data['vipLevel'] as String?),
              fallbackExpiry: _parseTimestamp(data['vipExpiresAt']),
            );
            final isPremiumFlag = (data['isPremium'] as bool?) ?? false;
            final typingPreviewPremium =
                (data['typingPreviewPremium'] as bool?) ?? false;
            final ultraPass = (data['ultraPass'] as bool?) ?? false;
            final hasVipAccess = vipStatus.tier != 'none' && vipStatus.isActive;
            final hasPreviewAccess =
                isPremiumFlag || typingPreviewPremium || hasVipAccess;
            _updateViewerAccess(hasPreviewAccess);
            final canSwipeDelete =
                isPremiumFlag || ultraPass || typingPreviewPremium || hasVipAccess;
            _updateSwipeDeleteAccess(canSwipeDelete);
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('TypingPreviewService user listen error: $error');
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stackTrace),
            );
          },
        );
  }

  void _listenToPrivacyDoc(String uid) {
    _privacySub?.cancel();
    final doc = _firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('privacy');
    _privacySub = doc.snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        final share = (data?['shareTypingPreview'] as bool?) ?? false;
        _updateSharePreference(share);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('TypingPreviewService privacy listen error: $error');
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
    );
  }

  void _updateViewerAccess(bool value) {
    if (_viewerHasPreviewAccess == value) {
      return;
    }
    _viewerHasPreviewAccess = value;
    if (!_viewAccessController.isClosed) {
      _viewAccessController.add(value);
    }
  }

  void _updateSharePreference(bool value) {
    if (_shareTypingPreview == value) {
      return;
    }
    _shareTypingPreview = value;
    if (!value) {
      _cancelPending();
      final uid = _currentUid;
      if (uid == null) {
        return;
      }
      for (final conversationId in List<String>.from(_activeConversations)) {
        unawaited(_clearRemotePreview(conversationId, uid));
      }
    }
  }

  void _updateSwipeDeleteAccess(bool value) {
    if (_canSwipeDelete == value) {
      return;
    }
    _canSwipeDelete = value;
  }

  Future<void> sendTypingPreview({
    required String conversationId,
    required String text,
  }) async {
    final uid = _currentUid;
    if (uid == null) {
      return;
    }
    final sanitized = _sanitize(text);
    final length = sanitized.length;
    if (!_canSend) {
      debugPrint(
        'TypingPreviewService: skip send for $conversationId (uid: $uid, length: $length) - shareTypingPreview disabled',
      );
      return;
    }
    final previous = _pending[conversationId]?.latestText;
    if (previous != sanitized) {
      debugPrint(
        'TypingPreviewService: queue preview update for $conversationId (uid: $uid, length: $length)',
      );
    }
    _scheduleWrite(conversationId, sanitized);
  }

  Stream<TypingPreviewState> watchTypingPreview({
    required String conversationId,
    required String otherUserId,
  }) {
    final doc = _firestore
        .collection('dm_threads')
        .doc(conversationId)
        .collection('typing_previews')
        .doc(otherUserId);
    final controller = StreamController<TypingPreviewState>();
    String? lastLoggedText;
    bool loggedFallback = false;
    TypingPreview? latestPreview;

    void emitState() {
      if (controller.isClosed) {
        return;
      }
      controller.add(
        TypingPreviewState(
          preview: _viewerHasPreviewAccess ? latestPreview : null,
          rawPreview: latestPreview,
          canViewPreview: _viewerHasPreviewAccess,
        ),
      );
    }

    StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? docSub;
    StreamSubscription<bool>? viewAccessSub;

    controller.onListen = () {
      viewAccessSub = _viewAccessController.stream.listen((_) {
        if (!_viewerHasPreviewAccess && !loggedFallback) {
          debugPrint(
            'TypingPreviewService: view access revoked for $conversationId (other: $otherUserId) - falling back',
          );
          loggedFallback = true;
          lastLoggedText = null;
        }
        emitState();
      });
      docSub = doc.snapshots().listen(
        (snapshot) {
          final data = snapshot.data();
          if (data == null) {
            if (!loggedFallback) {
              debugPrint(
                'TypingPreviewService: fallback typing indicator for $conversationId (other: $otherUserId) - no data',
              );
              loggedFallback = true;
            }
            lastLoggedText = null;
            latestPreview = null;
            emitState();
            return;
          }
          final text = (data['text'] as String?) ?? '';
          final trimmed = text.trim();
          if (trimmed.isEmpty) {
            if (!loggedFallback) {
              debugPrint(
                'TypingPreviewService: fallback typing indicator for $conversationId (other: $otherUserId) - empty text',
              );
              loggedFallback = true;
            }
            lastLoggedText = null;
            latestPreview = null;
            emitState();
            return;
          }
          if (lastLoggedText != trimmed) {
            debugPrint(
              'TypingPreviewService: received preview for $conversationId (other: $otherUserId, length: ${trimmed.length})',
            );
            lastLoggedText = trimmed;
          }
          loggedFallback = false;
          latestPreview = TypingPreview.fromSnapshot(snapshot);
          emitState();
        },
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
          debugPrint('TypingPreviewService preview listen error: $error');
          FlutterError.reportError(
            FlutterErrorDetails(exception: error, stack: stackTrace),
          );
        },
      );
      emitState();
    };

    controller.onCancel = () async {
      await docSub?.cancel();
      await viewAccessSub?.cancel();
      if (!controller.hasListener) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _userSub?.cancel();
    await _privacySub?.cancel();
    _cancelPending();
    await _viewAccessController.close();
  }

  void _cancelPending() {
    for (final entry in _pending.values) {
      entry.timer?.cancel();
    }
    _pending.clear();
  }

  void _scheduleWrite(String conversationId, String text) {
    final entry = _pending.putIfAbsent(conversationId, () => _PendingPreview());
    entry.latestText = text;
    entry.timer?.cancel();
    entry.timer = Timer(_kPreviewThrottle, () {
      entry.timer = null;
      unawaited(_commitPreview(conversationId));
    });
  }

  Future<void> _commitPreview(String conversationId) async {
    final entry = _pending[conversationId];
    final uid = _currentUid;
    if (entry == null || uid == null) {
      return;
    }
    final text = entry.latestText ?? '';
    try {
      if (!_canSend) {
        await _clearRemotePreview(conversationId, uid);
        return;
      }
      if (text.isEmpty) {
        await _clearRemotePreview(conversationId, uid);
        return;
      }
      final doc = _firestore
          .collection('dm_threads')
          .doc(conversationId)
          .collection('typing_previews')
          .doc(uid);
      await doc.set(<String, dynamic>{
        'userId': uid,
        'text': text,
        'updatedAt': cf.FieldValue.serverTimestamp(),
      }, cf.SetOptions(merge: true));
      _activeConversations.add(conversationId);
    } catch (error, stackTrace) {
      debugPrint('TypingPreviewService commit error: $error');
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    } finally {
      if (entry.timer == null && entry.latestText == text) {
        _pending.remove(conversationId);
      }
    }
  }

  Future<void> _clearRemotePreview(String conversationId, String uid) async {
    try {
      final doc = _firestore
          .collection('dm_threads')
          .doc(conversationId)
          .collection('typing_previews')
          .doc(uid);
      await doc.delete();
    } catch (error, stackTrace) {
      if (error is cf.FirebaseException && error.code == 'not-found') {
        return;
      }
      debugPrint('TypingPreviewService clear error: $error');
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stackTrace),
      );
    } finally {
      _activeConversations.remove(conversationId);
    }
  }

  String _sanitize(String raw) {
    final trimmed = raw.characters.take(_kMaxPreviewLength).toString();
    return trimmed;
  }
}

class _PendingPreview {
  String? latestText;
  Timer? timer;
}

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
