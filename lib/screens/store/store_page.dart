import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/store_product.dart';
import '../../widgets/store/product_card.dart';
import 'store_strings.dart';

class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  final List<StoreProduct> _products = <StoreProduct>[];
  final Set<String> _busyProductIds = <String>{};

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

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
      }
    });
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
      final callable =
          _functions.httpsCallable('createCheckoutSession');
      final result = await callable.call(<String, dynamic>{
        'productId': product.id,
      });
      final data = result.data;
      final urlString = data is Map<String, dynamic>
          ? data['url'] as String?
          : data['url']?.toString();
      if (urlString == null || urlString.isEmpty) {
        throw Exception('Missing checkout url');
      }
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('launch_failed');
      }
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
    return RefreshIndicator(
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 900
              ? 3
              : constraints.maxWidth > 600
                  ? 2
                  : 1;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final product = _products[index];
                      final busy = _busyProductIds.contains(product.id);
                      return ProductCard(
                        product: product,
                        busy: busy,
                        onBuy: () => _buy(product),
                        onView: () => _openProduct(product),
                      );
                    },
                    childCount: _products.length,
                  ),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: crossAxisCount == 1 ? 1.4 : 0.95,
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
