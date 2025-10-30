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
}
// CODEX-END:STORE_CACHE_SERVICE
