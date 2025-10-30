// CODEX-BEGIN:STORE_CACHE_SERVICE
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'firestore_service.dart';

class CacheService {
  CacheService._();

  static final CacheService instance = CacheService._();

  static const Duration _storeTtl = Duration(minutes: 30);
  static const String _storeDataKey = 'store.firstPage.data';
  static const String _storeTsKey = 'store.firstPage.ts';

  // CODEX-BEGIN:WALLET_CACHE_FIELDS
  static const String _walletDataKeyPrefix = 'wallet.summary.';
  WalletSummary? _memoryWalletSummary;
  String? _memoryWalletUid;
  // CODEX-END:WALLET_CACHE_FIELDS

  // CODEX-BEGIN:TRANSLATION_CACHE_FIELDS
  static const String _translationKeyPrefix = 'translator.message.';
  final Map<String, Map<String, String>> _memoryTranslations = {};
  // CODEX-END:TRANSLATION_CACHE_FIELDS

  List<StoreItem>? _memoryStoreFirstPage;
  DateTime? _memoryStoreFirstPageAt;

  Future<List<StoreItem>?> getStoreFirstPage() async {
    final now = DateTime.now();
    final memoryItems = _memoryStoreFirstPage;
    final memoryAt = _memoryStoreFirstPageAt;
    if (memoryItems != null && memoryAt != null) {
      if (now.difference(memoryAt) < _storeTtl) {
        return List<StoreItem>.from(memoryItems);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final tsMillis = prefs.getInt(_storeTsKey);
    if (tsMillis == null) {
      return null;
    }
    final storedAt = DateTime.fromMillisecondsSinceEpoch(tsMillis);
    if (now.difference(storedAt) >= _storeTtl) {
      await _clearStoreFirstPage(prefs);
      return null;
    }
    final raw = prefs.getString(_storeDataKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final items = <StoreItem>[];
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          items.add(StoreItem.fromJson(entry));
        } else if (entry is Map) {
          items.add(StoreItem.fromJson(
              Map<String, dynamic>.from(entry as Map<dynamic, dynamic>)));
        }
      }
      _memoryStoreFirstPage = List<StoreItem>.unmodifiable(items);
      _memoryStoreFirstPageAt = storedAt;
      return List<StoreItem>.from(items);
    } catch (_) {
      await _clearStoreFirstPage(prefs);
      return null;
    }
  }

  Future<void> saveStoreFirstPage(List<StoreItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final payload = items.map((e) => e.toJson()).toList();
    _memoryStoreFirstPage = List<StoreItem>.unmodifiable(items);
    _memoryStoreFirstPageAt = now;
    await prefs.setString(_storeDataKey, jsonEncode(payload));
    await prefs.setInt(_storeTsKey, now.millisecondsSinceEpoch);
  }

  Future<void> clearStoreFirstPage() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearStoreFirstPage(prefs);
  }

  Future<void> _clearStoreFirstPage(SharedPreferences prefs) async {
    _memoryStoreFirstPage = null;
    _memoryStoreFirstPageAt = null;
    await prefs.remove(_storeDataKey);
    await prefs.remove(_storeTsKey);
  }

  // CODEX-BEGIN:WALLET_CACHE_METHODS
  Future<WalletSummary?> getCachedWallet(String uid) async {
    if (uid.isEmpty) {
      return null;
    }
    if (_memoryWalletUid == uid && _memoryWalletSummary != null) {
      return _memoryWalletSummary;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_walletDataKeyPrefix$uid');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final summary = WalletSummary.fromJson(decoded);
        _memoryWalletSummary = summary;
        _memoryWalletUid = uid;
        return summary;
      }
      if (decoded is Map) {
        final summary = WalletSummary.fromJson(
            Map<String, dynamic>.from(decoded as Map<dynamic, dynamic>));
        _memoryWalletSummary = summary;
        _memoryWalletUid = uid;
        return summary;
      }
    } catch (_) {
      await prefs.remove('$_walletDataKeyPrefix$uid');
    }
    return null;
  }

  Future<void> saveWallet(String uid, WalletSummary summary) async {
    if (uid.isEmpty) {
      return;
    }
    _memoryWalletUid = uid;
    _memoryWalletSummary = summary;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_walletDataKeyPrefix$uid',
      jsonEncode(summary.toJson()),
    );
  }

  Future<void> clearWallet(String uid) async {
    if (uid.isEmpty) {
      return;
    }
    if (_memoryWalletUid == uid) {
      _memoryWalletUid = null;
      _memoryWalletSummary = null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_walletDataKeyPrefix$uid');
  }
  // CODEX-END:WALLET_CACHE_METHODS

  // CODEX-BEGIN:TRANSLATION_CACHE_METHODS
  Future<String?> getCachedTranslation(String messageId, String lang) async {
    if (messageId.isEmpty || lang.isEmpty) {
      return null;
    }
    final inMemory = _memoryTranslations[messageId]?[lang];
    if (inMemory != null) {
      return inMemory;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_translationKeyPrefix$messageId::$lang');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    _memoryTranslations.putIfAbsent(messageId, () => {})[lang] = raw;
    return raw;
  }

  Future<void> saveTranslation(String messageId, String lang, String text) async {
    if (messageId.isEmpty || lang.isEmpty || text.isEmpty) {
      return;
    }
    _memoryTranslations.putIfAbsent(messageId, () => {})[lang] = text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_translationKeyPrefix$messageId::$lang', text);
  }
  // CODEX-END:TRANSLATION_CACHE_METHODS
}
// CODEX-END:STORE_CACHE_SERVICE
