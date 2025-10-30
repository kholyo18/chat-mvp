// CODEX-BEGIN:WALLET_CONTROLLER
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/cache_service.dart';
import '../../services/firestore_service.dart';

class WalletController extends ChangeNotifier {
  WalletController({
    required FirestoreService firestoreService,
    required CacheService cacheService,
  })  : _firestoreService = firestoreService,
        _cacheService = cacheService;

  final FirestoreService _firestoreService;
  final CacheService _cacheService;

  static const int _pageSize = 20;
  static const int _maxTransactions = 50;

  String? _uid;
  bool _initialized = false;
  bool loading = false;
  bool refreshing = false;
  bool loadingMore = false;
  bool addingBalance = false;
  bool hasMore = true;

  WalletSummary? summary;
  List<WalletTransaction> transactions = <WalletTransaction>[];
  String? errorMessage;

  StreamSubscription<WalletSummary?>? _walletSubscription;
  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;

  Future<void> init(String uid) async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _uid = uid;

    final cached = await _cacheService.getCachedWallet(uid);
    if (cached != null) {
      summary = cached;
      notifyListeners();
    }

    _walletSubscription = _firestoreService.walletStream(uid).listen(
      (value) {
        summary = value;
        if (value != null) {
          unawaited(_cacheService.saveWallet(uid, value));
        }
        notifyListeners();
      },
      onError: (Object err) {
        errorMessage = err.toString();
        notifyListeners();
      },
    );

    await _loadTransactions(reset: true);
  }

  @override
  void dispose() {
    _walletSubscription?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_uid == null) return;
    refreshing = true;
    notifyListeners();
    await _loadTransactions(reset: true);
    refreshing = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_uid == null) return;
    if (!hasMore) return;
    if (loadingMore) return;
    if (transactions.length >= _maxTransactions) {
      hasMore = false;
      notifyListeners();
      return;
    }
    loadingMore = true;
    notifyListeners();
    await _loadTransactions(reset: false);
    loadingMore = false;
    notifyListeners();
  }

  Future<bool> addBalance({
    required String packId,
    required int amount,
  }) async {
    if (_uid == null) return false;
    if (addingBalance) return false;
    addingBalance = true;
    notifyListeners();

    final result = await _firestoreService.simulateWalletTopUp(
      uid: _uid!,
      amount: amount,
      packId: packId,
    );

    if (result is SafeSuccess<WalletTransaction>) {
      final tx = result.value;
      transactions = <WalletTransaction>[tx, ...transactions];
      if (transactions.length > _maxTransactions) {
        transactions = transactions.sublist(0, _maxTransactions);
      }
      addingBalance = false;
      errorMessage = null;
      notifyListeners();
      return true;
    } else if (result is SafeFailure<WalletTransaction>) {
      errorMessage = result.message;
    } else {
      errorMessage = 'Unknown error';
    }

    addingBalance = false;
    notifyListeners();
    return false;
  }

  Future<void> _loadTransactions({required bool reset}) async {
    if (_uid == null) return;
    if (reset) {
      loading = true;
      notifyListeners();
    }

    final result = await _firestoreService.fetchWalletTransactions(
      uid: _uid!,
      limit: _pageSize,
      startAfter: reset ? null : _lastDocument,
    );

    if (result is SafeSuccess<WalletTransactionsPage>) {
      final page = result.value;
      if (reset) {
        transactions = List<WalletTransaction>.from(page.transactions);
      } else {
        final existingIds = transactions.map((e) => e.id).toSet();
        final merged = List<WalletTransaction>.from(transactions);
        for (final tx in page.transactions) {
          if (!existingIds.contains(tx.id)) {
            merged.add(tx);
          }
        }
        transactions = merged;
      }
      if (transactions.length > _maxTransactions) {
        transactions = transactions.sublist(0, _maxTransactions);
      }
      _lastDocument = page.lastDocument;
      hasMore = page.hasMore && transactions.length < _maxTransactions;
      errorMessage = null;
    } else if (result is SafeFailure<WalletTransactionsPage>) {
      errorMessage = result.message;
    } else {
      errorMessage = 'Unable to load transactions';
    }

    if (reset) {
      loading = false;
    }
    notifyListeners();
  }
}
// CODEX-END:WALLET_CONTROLLER
