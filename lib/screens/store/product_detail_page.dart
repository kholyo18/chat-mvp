import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/store_product.dart';
import '../../services/checkout_service.dart';
import 'store_strings.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  final String productId;
  final StoreProduct? initialProduct;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CheckoutService _checkoutService = CheckoutService();

  StoreProduct? _product;
  bool _loading = true;
  bool _processing = false;
  String? _error;
  String? _pendingCheckoutResumeMessageKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _product = widget.initialProduct;
    if (_product != null) {
      _loading = false;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _refreshPurchases() async {
    final user = FirebaseAuth.instance.currentUser;
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
    } catch (_) {}
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await _firestore
          .collection('store_products')
          .doc(widget.productId)
          .get();
      if (!doc.exists || doc.data()?['active'] != true) {
        throw Exception('not_found');
      }
      final product = StoreProduct.fromDoc(doc);
      if (!mounted) {
        return;
      }
      setState(() {
        _product = product;
        _loading = false;
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

  Future<void> _buy() async {
    if (_processing || _product == null) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(storeTr(context, 'not_signed_in'))),
      );
      return;
    }
    setState(() {
      _processing = true;
    });
    try {
      final product = _product;
      await _checkoutService.startCheckout(widget.productId);
      _pendingCheckoutResumeMessageKey =
          product != null && product.isVipProduct
              ? 'vip_resume_message'
              : 'coins_resume_message';
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
          _processing = false;
        });
      }
      await _refreshPurchases();
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(storeTr(context, 'store_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          storeTr(context, 'failed_to_load_store'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: Text(storeTr(context, 'retry')),
                        ),
                      ],
                    ),
                  ),
                )
              : product == null
                  ? Center(
                      child: Text(storeTr(context, 'failed_to_load_store')),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              color: theme.colorScheme.secondaryContainer,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.storefront_rounded,
                                size: 96,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            product.title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            product.subtitle,
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (product.description != null &&
                              product.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 16),
                              child: Text(
                                product.description!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          if (product.includesVip)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 16),
                              child: Chip(
                                label: Text(storeTr(context, 'includes_vip')),
                                avatar: const Icon(Icons.workspace_premium_rounded),
                              ),
                            ),
                          if (product.isVipProduct)
                            _VipBenefitsSection(tier: product.vipTier),
                          if (product.type == 'coins' && product.coinsAmount > 0)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(top: 12),
                              child: Text(
                                storeTr(
                                  context,
                                  'coins_amount',
                                  params: <String, String>{
                                    'coins': product.coinsAmount.toString(),
                                  },
                                ),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          const SizedBox(height: 24),
                          Builder(
                            builder: (context) {
                              final NumberFormat currencyFmt = (() {
                                try {
                                  return NumberFormat.simpleCurrency(
                                    name: product.currency,
                                  );
                                } catch (_) {
                                  return NumberFormat.simpleCurrency();
                                }
                              })();
                              final price = currencyFmt.format(product.price);
                              return Text(
                                '${storeTr(context, 'price')}: $price',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _processing ? null : _buy,
                              child: _processing
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(product.isVipProduct
                                      ? storeTr(context, 'buy_vip')
                                      : storeTr(context, 'buy')),
                            ),
                          ),
                          // TODO: Implement pro-rated upgrade pricing for future VIP upgrades.
                        ],
                      ),
                    ),
    );
  }
}

const Map<String, List<String>> _vipBenefitLookup = <String, List<String>>{
  'bronze': <String>[
    'Bronze badge on your profile',
    'Daily reward boost (Bronze tier)',
  ],
  'silver': <String>[
    'Silver badge on your profile',
    'Increased daily reward boost',
    'Access to VIP lounge chat',
  ],
  'gold': <String>[
    'Gold badge with premium flair',
    'Priority support from the Codex team',
    'Early access to new drops',
  ],
  'platinum': <String>[
    'Platinum badge and profile highlights',
    'Top-tier support & concierge',
    'Exclusive beta features and rooms',
  ],
};

class _VipBenefitsSection extends StatelessWidget {
  const _VipBenefitsSection({required this.tier});

  final String? tier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedTier = (tier ?? '').trim().toLowerCase();
    final benefits = _vipBenefitLookup[normalizedTier] ??
        <String>['Priority access to upcoming VIP perks.'];

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            storeTr(context, 'vip_benefits_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...benefits.map(
            (benefit) => Padding(
              padding: const EdgeInsetsDirectional.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8, top: 2),
                    child: Icon(Icons.check_circle_outline_rounded, size: 18),
                  ),
                  Expanded(
                    child: Text(
                      benefit,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
