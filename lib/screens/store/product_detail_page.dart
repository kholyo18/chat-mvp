import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/store_product.dart';
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
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  StoreProduct? _product;
  bool _loading = true;
  bool _processing = false;
  String? _error;

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
      final callable =
          _functions.httpsCallable('createCheckoutSession');
      final result = await callable.call(<String, dynamic>{
        'productId': widget.productId,
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
                              final NumberFormat formatter;
                              try {
                                formatter = NumberFormat.simpleCurrency(
                                  name: product.currency,
                                );
                              } catch (_) {
                                formatter = NumberFormat.simpleCurrency();
                              }
                              final price = formatter.format(product.price);
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
                                  : Text(storeTr(context, 'buy')),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
