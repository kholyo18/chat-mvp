// CODEX-BEGIN:TRANSLATOR_SERVICE
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/cache_service.dart';
import '../../services/translate_service.dart';

class TranslatorService extends ChangeNotifier {
  TranslatorService({
    CacheService? cache,
    TranslateService? translateService,
  })  : _cache = cache ?? CacheService.instance,
        _translateService = translateService ?? const TranslateService();

  final CacheService _cache;
  final TranslateService _translateService;

  String targetLang = 'ar';
  bool autoTranslateEnabled = true;

  final Map<String, Map<String, String>> _memoryTranslations = <String, Map<String, String>>{};
  final Set<String> _pendingTranslations = <String>{};
  final Map<String, bool?> _roomAutoOverrides = <String, bool?>{};
  final Map<String, String?> _roomLangOverrides = <String, String?>{};
  final Set<String> _showOriginalMessages = <String>{};

  StreamSubscription<User?>? _authSub;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  String? _currentUid;

  Future<void> load() async {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuth,
      onError: (Object err, StackTrace stack) {
        debugPrint('TranslatorService.auth listen error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      },
    );
    await _handleAuth(FirebaseAuth.instance.currentUser);
  }

  Future<void> _handleAuth(User? user) async {
    _settingsSub?.cancel();
    _currentUid = user?.uid;
    if (user == null) {
      targetLang = 'ar';
      autoTranslateEnabled = true;
      _memoryTranslations.clear();
      _roomAutoOverrides.clear();
      _roomLangOverrides.clear();
      _showOriginalMessages.clear();
      notifyListeners();
      return;
    }
    try {
      await _ensureSettingsDoc(user.uid);
      _listenToSettings(user.uid);
    } catch (err, stack) {
      debugPrint('TranslatorService._handleAuth error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }

  Future<void> _ensureSettingsDoc(String uid) async {
    try {
      final settingsRef = cf.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('app');
      final settingsSnap = await settingsRef.get();
      if (!settingsSnap.exists) {
        String? fallbackLang;
        bool? fallbackAuto;
        try {
          final userSnap = await cf.FirebaseFirestore.instance.collection('users').doc(uid).get();
          final data = userSnap.data();
          if (data != null) {
            final i18n = data['i18n'];
            if (i18n is Map) {
              final i18nMap = Map<String, dynamic>.from(i18n as Map<dynamic, dynamic>);
              final lang = i18nMap['target'];
              if (lang is String && lang.isNotEmpty) {
                fallbackLang = lang;
              }
              final auto = i18nMap['auto'];
              if (auto is bool) {
                fallbackAuto = auto;
              }
            }
          }
        } catch (err, stack) {
          debugPrint('TranslatorService._ensureSettingsDoc migration error: $err');
          FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
        }
        await settingsRef.set(
          {
            'autoTranslate': fallbackAuto ?? autoTranslateEnabled,
            'targetLang': fallbackLang ?? targetLang,
          },
          cf.SetOptions(merge: true),
        );
      } else {
        final data = settingsSnap.data();
        if (data != null) {
          applyRemoteSettings(data);
        }
      }
    } catch (err, stack) {
      debugPrint('TranslatorService._ensureSettingsDoc error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }

  void _listenToSettings(String uid) {
    _settingsSub?.cancel();
    _settingsSub = cf.FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('app')
        .snapshots()
        .listen(
      (snap) {
        final data = snap.data();
        if (data != null) {
          applyRemoteSettings(data);
        }
      },
      onError: (Object err, StackTrace stack) {
        debugPrint('TranslatorService._listenToSettings error: $err');
        FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      },
    );
  }

  void applyRemoteSettings(Map<String, dynamic> data) {
    var updated = false;
    final target = data['targetLang'] ?? data['target'];
    if (target is String && target.isNotEmpty && target != targetLang) {
      targetLang = target;
      updated = true;
    }
    final auto = data['autoTranslate'] ?? data['auto'];
    if (auto is bool && auto != autoTranslateEnabled) {
      autoTranslateEnabled = auto;
      updated = true;
    }
    if (updated) {
      notifyListeners();
    }
  }

  Future<void> setLang(String code) async {
    if (code == targetLang) {
      return;
    }
    targetLang = code;
    _memoryTranslations.clear();
    notifyListeners();
    final uid = _currentUid;
    if (uid == null) {
      return;
    }
    try {
      await cf.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('app')
          .set({'targetLang': code}, cf.SetOptions(merge: true));
    } catch (err, stack) {
      debugPrint('TranslatorService.setLang error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }

  Future<void> setAuto(bool value) async {
    if (value == autoTranslateEnabled) {
      return;
    }
    autoTranslateEnabled = value;
    notifyListeners();
    final uid = _currentUid;
    if (uid == null) {
      return;
    }
    try {
      await cf.FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('app')
          .set({'autoTranslate': value}, cf.SetOptions(merge: true));
    } catch (err, stack) {
      debugPrint('TranslatorService.setAuto error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
  }

  void applyRoomOverride(String roomId, {bool? auto, String? targetLang}) {
    var updated = false;
    if (auto == null) {
      if (_roomAutoOverrides.remove(roomId) != null) {
        updated = true;
      }
    } else {
      final previous = _roomAutoOverrides[roomId];
      if (previous != auto) {
        _roomAutoOverrides[roomId] = auto;
        updated = true;
      }
    }
    if (targetLang == null || targetLang.isEmpty) {
      if (_roomLangOverrides.remove(roomId) != null) {
        updated = true;
      }
    } else {
      final previous = _roomLangOverrides[roomId];
      if (previous != targetLang) {
        _roomLangOverrides[roomId] = targetLang;
        updated = true;
      }
    }
    if (updated) {
      notifyListeners();
    }
  }

  void clearRoomOverride(String roomId) {
    final removedAuto = _roomAutoOverrides.remove(roomId);
    final removedLang = _roomLangOverrides.remove(roomId);
    if (removedAuto != null || removedLang != null) {
      notifyListeners();
    }
  }

  bool isAutoEnabledForRoom(String roomId) {
    final override = _roomAutoOverrides[roomId];
    if (override != null) {
      return override;
    }
    return autoTranslateEnabled;
  }

  String effectiveLangForRoom(String roomId) {
    final override = _roomLangOverrides[roomId];
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return targetLang;
  }

  String? getCachedTranslation(String messageId, String lang) {
    return _memoryTranslations[messageId]?[lang];
  }

  void primeTranslation(String messageId, String lang, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final langMap = _memoryTranslations.putIfAbsent(messageId, () => <String, String>{});
    if (langMap[lang] == trimmed) {
      return;
    }
    langMap[lang] = trimmed;
    unawaited(_cache.saveTranslation(messageId, lang, trimmed));
    notifyListeners();
  }

  void requestTranslation({
    required String roomId,
    required String messageId,
    required String text,
  }) {
    if (!isAutoEnabledForRoom(roomId)) {
      return;
    }
    if (_showOriginalMessages.contains(messageId)) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final lang = effectiveLangForRoom(roomId);
    final existing = getCachedTranslation(messageId, lang);
    if (existing != null) {
      return;
    }
    final key = '$messageId::$lang';
    if (_pendingTranslations.contains(key)) {
      return;
    }
    _pendingTranslations.add(key);
    unawaited(_performTranslation(messageId: messageId, lang: lang, text: trimmed, key: key));
  }

  Future<void> _performTranslation({
    required String messageId,
    required String lang,
    required String text,
    required String key,
  }) async {
    try {
      final cached = await _cache.getCachedTranslation(messageId, lang);
      if (cached != null && cached.trim().isNotEmpty) {
        primeTranslation(messageId, lang, cached);
        return;
      }
      final translated = await _translateService.translate(text, lang);
      if (translated == null) {
        return;
      }
      if (translated.trim().isEmpty || translated.trim() == text.trim()) {
        return;
      }
      primeTranslation(messageId, lang, translated);
    } catch (err, stack) {
      debugPrint('TranslatorService._performTranslation error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    } finally {
      _pendingTranslations.remove(key);
    }
  }

  bool isShowingOriginal(String messageId) => _showOriginalMessages.contains(messageId);

  void showOriginal(String messageId) {
    if (_showOriginalMessages.add(messageId)) {
      notifyListeners();
    }
  }

  void showTranslation(String messageId) {
    if (_showOriginalMessages.remove(messageId)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _settingsSub?.cancel();
    super.dispose();
  }
}
// CODEX-END:TRANSLATOR_SERVICE
