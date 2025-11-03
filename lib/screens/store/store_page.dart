import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/store_product.dart';
import '../../services/checkout_service.dart';
import '../../widgets/store/product_card.dart';
import 'store_strings.dart';

enum StoreCategory { vip, coins, themes, subscriptions }

const _storeIds = <StoreCategory, String>{
  StoreCategory.vip: 'vip',
  StoreCategory.coins: 'coins',
  StoreCategory.themes: 'themes',
  StoreCategory.subscriptions: 'subscriptions',
};

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CheckoutService _checkoutService = CheckoutService();

  final List<StoreProduct> _products = <StoreProduct>[];
  final Set<String> _busyProductIds = <String>{};

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _selectedCategory = _StoreCategoryFilter.all.id;
  String? _pendingCheckoutResumeMessageKey;
  DateTime? _lastVipNoticeShownAt;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _userSubscription;
  Map<String, dynamic> _userProfile = <String, dynamic>{};

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listenUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPurchases());
      if (_pendingCheckoutResumeMessageKey != null) {
        _showResumeSnackBar();
      }
    }
  }

  Future<void> _listenUser() async {
    final user = _currentUser;
    if (user == null) {
      return;
    }
    await _userSubscription?.cancel();
    _userSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      _userProfile = snapshot.data() ?? <String, dynamic>{};
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeShowVipNotice();
        });
      }
    });
  }

  void _maybeShowVipNotice() {
    if (!mounted) {
      return;
    }
    final notice = (_userProfile['vipNotice'] as String? ?? '').trim();
    if (notice != 'higher-tier-exists') {
      _lastVipNoticeShownAt = null;
      return;
    }
    DateTime? noticeAt;
    final raw = _userProfile['vipNoticeAt'];
    if (raw is Timestamp) {
      noticeAt = raw.toDate();
    } else if (raw is DateTime) {
      noticeAt = raw;
    }

    final lastShown = _lastVipNoticeShownAt;
    if (noticeAt != null && lastShown != null && !noticeAt.isAfter(lastShown)) {
      return;
    }

    _lastVipNoticeShownAt = noticeAt ?? DateTime.now();

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(storeTr(context, 'vip_notice_higher')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = await _firestore
          .collection('store_products')
          .where('active', isEqualTo: true)
          .orderBy('sort')
          .get();
      final products = query.docs
          .map(StoreProduct.fromDoc)
          .where((product) => product.active)
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _products
          ..clear()
          ..addAll(products);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() {
      _refreshing = true;
    });
    try {
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshPurchases() async {
    final user = _currentUser;
    if (user == null) {
      return;
    }
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('purchases')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
    } catch (_) {
      // Ignore failures – store page remains usable.
    }
  }

  Future<void> _buy(StoreProduct product) async {
    if (_busyProductIds.contains(product.id)) {
      return;
    }
    final user = _currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(storeTr(context, 'not_signed_in'))),
        );
      }
      return;
    }
    setState(() {
      _busyProductIds.add(product.id);
    });
    try {
      await _checkoutService.startCheckout(product.id);
      _pendingCheckoutResumeMessageKey =
          product.isVipProduct ? 'vip_resume_message' : 'coins_resume_message';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(storeTr(context, 'complete_in_browser'))),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(storeTr(context, 'failed_to_start_checkout'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyProductIds.remove(product.id);
        });
      }
      await _refreshPurchases();
    }
  }

  void _showResumeSnackBar() {
    if (!mounted) {
      return;
    }
    final messageKey = _pendingCheckoutResumeMessageKey;
    if (messageKey == null) {
      return;
    }
    _pendingCheckoutResumeMessageKey = null;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(storeTr(context, messageKey)),
          action: SnackBarAction(
            label: storeTr(context, 'refresh'),
            onPressed: () {
              unawaited(_refreshPurchases());
            },
          ),
        ),
      );
  }

  List<StoreProduct> get _filteredProducts {
    if (_selectedCategory == _StoreCategoryFilter.all.id) {
      return List<StoreProduct>.from(_products);
    }
    return _products.where(_matchesSelectedCategory).toList();
  }

  bool _matchesSelectedCategory(StoreProduct product) {
    final filter = _StoreCategoryFilter.byId(_selectedCategory);
    final storeCategory = filter.storeCategory;
    if (storeCategory == null) {
      return true;
    }
    switch (storeCategory) {
      case StoreCategory.coins:
        final categoryId = _storeIds[StoreCategory.coins]!;
        return product.type == categoryId;
      case StoreCategory.vip:
        final categoryId = _storeIds[StoreCategory.vip]!;
        return product.type == categoryId;
      case StoreCategory.themes:
        final categoryId = _storeIds[StoreCategory.themes]!;
        return product.type == categoryId ||
            product.type == 'theme' ||
            product.type == 'feature';
      case StoreCategory.subscriptions:
        final categoryId = _storeIds[StoreCategory.subscriptions]!;
        return product.type == categoryId || product.type == 'subscription';
    }
  }

  Widget _buildCategoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      child: Row(
        children: _StoreCategoryFilter.values.map((category) {
          final selected = _selectedCategory == category.id;
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              label: Text(storeTr(context, category.labelKey)),
              selected: selected,
              onSelected: (value) {
                if (!value) {
                  return;
                }
                setState(() {
                  _selectedCategory = category.id;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openProduct(StoreProduct product) {
    Navigator.of(context).pushNamed(
      '/store/product/${product.id}',
      arguments: product.toMap(),
    );
  }

  void _openPurchases() {
    Navigator.of(context).pushNamed('/store/purchases');
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _products.isEmpty) {
      return _ErrorState(
        message: storeTr(context, 'failed_to_load_store'),
        onRetry: _load,
      );
    }
    if (_products.isEmpty) {
      return Center(
        child: Text(storeTr(context, 'no_products')),
      );
    }
    final filteredProducts = _filteredProducts;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 900
              ? 3
              : constraints.maxWidth > 600
                  ? 2
                  : 1;
          final currentVipTier = (_userProfile['vipTier'] as String? ?? '').trim();
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildCategoryChips(),
              ),
              if (filteredProducts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(storeTr(context, 'no_products')),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = filteredProducts[index];
                        final busy = _busyProductIds.contains(product.id);
                        return ProductCard(
                          product: product,
                          currentVipTier: currentVipTier,
                          busy: busy,
                          onBuy: () => _buy(product),
                          onView: () => _openProduct(product),
                        );
                      },
                      childCount: filteredProducts.length,
                    ),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio:
                          crossAxisCount == 1 ? 1.4 : 0.95,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final coins = _userProfile['coins'];
    final vipTier = (_userProfile['vipTier'] as String?)?.toUpperCase();

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(storeTr(context, 'store_title')),
        actions: [
          IconButton(
            onPressed: _openPurchases,
            icon: const Icon(Icons.receipt_long_rounded),
            tooltip: storeTr(context, 'view_purchases'),
          ),
        ],
      ),
      body: user == null
          ? Center(child: Text(storeTr(context, 'not_signed_in')))
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          label: 'Coins',
                          value: NumberFormat.compact().format(
                            coins is num ? coins.toInt() : 0,
                          ),
                          icon: Icons.monetization_on_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          label: 'VIP',
                          value: vipTier ?? '—',
                          icon: Icons.workspace_premium_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody()),
              ],
            ),
      floatingActionButton: _error != null && _products.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(storeTr(context, 'retry')),
            )
          : null,
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(storeTr(context, 'retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCategoryFilter {
  const _StoreCategoryFilter._(this.id, this.labelKey, this.storeCategory);

  final String id;
  final String labelKey;
  final StoreCategory? storeCategory;

  static const _StoreCategoryFilter all =
      _StoreCategoryFilter._('all', 'category_all', null);
  static const _StoreCategoryFilter coins = _StoreCategoryFilter._(
    'coins',
    'category_coins',
    StoreCategory.coins,
  );
  static const _StoreCategoryFilter vip = _StoreCategoryFilter._(
    'vip',
    'category_vip',
    StoreCategory.vip,
  );
  static const _StoreCategoryFilter themes = _StoreCategoryFilter._(
    'themes',
    'category_themes',
    StoreCategory.themes,
  );
  static const _StoreCategoryFilter subscriptions = _StoreCategoryFilter._(
    'subscriptions',
    'category_subscriptions',
    StoreCategory.subscriptions,
  );

  static const List<_StoreCategoryFilter> values = <_StoreCategoryFilter>[
    all,
    coins,
    vip,
    themes,
    subscriptions,
  ];

  static _StoreCategoryFilter byId(String id) {
    return values.firstWhere(
      (filter) => filter.id == id,
      orElse: () => all,
    );
  }
}
