import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/store_product.dart';
import 'store_strings.dart';

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({super.key});

  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<_PurchaseRecord> _purchases = <_PurchaseRecord>[];
  Map<String, StoreProduct> _products = <String, StoreProduct>{};

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final firestore = FirebaseFirestore.instance;
      final purchasesQuery = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('purchases')
          .orderBy('createdAt', descending: true)
          .get();
      final productsQuery = await firestore
          .collection('store_products')
          .where('active', isEqualTo: true)
          .get();
      final products = <String, StoreProduct>{
        for (final doc in productsQuery.docs)
          doc.id: StoreProduct.fromDoc(doc),
      };
      final purchases = purchasesQuery.docs
          .map((doc) => _PurchaseRecord.fromDoc(doc))
          .toList();
      if (!mounted) {
        return;
      }
      setState(() {
        _products = products;
        _purchases = purchases;
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

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(storeTr(context, 'purchases_title')),
      ),
      body: user == null
          ? Center(child: Text(storeTr(context, 'not_signed_in')))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              storeTr(context, 'failed_to_load_purchases'),
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
                  : _purchases.isEmpty
                      ? Center(child: Text(storeTr(context, 'no_purchases')))
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            padding:
                                const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 32),
                            itemBuilder: (context, index) {
                              final purchase = _purchases[index];
                              final product = _products[purchase.productId];
                              return _PurchaseTile(
                                purchase: purchase,
                                product: product,
                              );
                            },
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemCount: _purchases.length,
                          ),
                        ),
    );
  }
}

class _PurchaseRecord {
  _PurchaseRecord({
    required this.id,
    required this.productId,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.fulfilledAt,
    required this.sessionId,
  });

  final String id;
  final String productId;
  final int amountCents;
  final String currency;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? fulfilledAt;
  final String sessionId;

  factory _PurchaseRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _PurchaseRecord(
      id: doc.id,
      productId: (data['productId'] as String? ?? '').trim(),
      amountCents: (data['amount_cents'] as num? ?? 0).toInt(),
      currency: (data['currency'] as String? ?? 'USD').toUpperCase(),
      status: (data['status'] as String? ?? '').trim(),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      fulfilledAt: data['fulfilledAt'] is Timestamp
          ? data['fulfilledAt'] as Timestamp
          : null,
      sessionId: (data['stripe_checkout_session'] as String? ?? '').trim(),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.purchase,
    required this.product,
  });

  final _PurchaseRecord purchase;
  final StoreProduct? product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final NumberFormat formatter;
    try {
      formatter = NumberFormat.simpleCurrency(name: purchase.currency);
    } catch (_) {
      formatter = NumberFormat.simpleCurrency();
    }
    final priceLabel = formatter.format(purchase.amountCents / 100.0);
    final createdAt = purchase.createdAt?.toDate();
    final dateLabel = createdAt != null
        ? DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
            .add_jm()
            .format(createdAt)
        : '';
    final statusKey = purchase.status == 'refunded'
        ? 'purchase_status_refunded'
        : 'purchase_status_paid';

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product?.title ?? purchase.productId,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            product?.subtitle ?? '',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Chip(
                backgroundColor: purchase.status == 'refunded'
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                label: Text(
                  storeTr(context, statusKey),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: purchase.status == 'refunded'
                        ? theme.colorScheme.onErrorContainer
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(priceLabel, style: theme.textTheme.bodyMedium),
              const Spacer(),
              if (dateLabel.isNotEmpty)
                Text(
                  dateLabel,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
