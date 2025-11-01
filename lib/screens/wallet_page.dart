import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/coin_transaction.dart';
import '../services/wallet_service.dart';
import '../widgets/common/coins_pill.dart';
import '../widgets/common/transaction_tile.dart';
import '../widgets/common/vip_chip.dart';
import 'coins_shop_page.dart';
import 'vip_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const _pageSize = 20;

  final WalletService _walletService = WalletService();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  final List<CoinTransaction> _transactions = <CoinTransaction>[];

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (_currentUser == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await _walletService.fetchPage(
        uid: _currentUser!.uid,
        limit: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _transactions
          ..clear()
          ..addAll(list);
        _cursor = list.isNotEmpty ? list.last.snapshot : null;
        _hasMore = list.length == _pageSize;
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

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _currentUser == null || _cursor == null) {
      return;
    }
    setState(() {
      _loadingMore = true;
    });
    try {
      final list = await _walletService.fetchPage(
        uid: _currentUser!.uid,
        limit: _pageSize,
        startAfter: _cursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _transactions.addAll(list);
        _cursor = list.isNotEmpty ? list.last.snapshot : _cursor;
        _hasMore = list.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _loadingMore) return;
    final threshold = 120.0;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= threshold) {
      _loadMore();
    }
  }

  Future<void> _refresh() async {
    await _loadInitial();
  }

  Future<void> _handleEarn(int amount, String note) async {
    if (_currentUser == null) return;
    try {
      await _walletService.earn(amount, uid: _currentUser!.uid, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $amount coins')),
      );
      await _refresh();
    } on WalletServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _handleSpend(int amount, String note) async {
    if (_currentUser == null) return;
    try {
      await _walletService.spend(amount, uid: _currentUser!.uid, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spent $amount coins')),
      );
      await _refresh();
    } on WalletInsufficientBalanceException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient balance')),
      );
    } on WalletServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  void _openEarnSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.card_giftcard_rounded),
                title: const Text('Daily bonus (+50)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleEarn(50, 'Daily bonus');
                },
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_fill_rounded),
                title: const Text('Watch ad (+30)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleEarn(30, 'Ad reward');
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_add_rounded),
                title: const Text('Invite friend (+100)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _handleEarn(100, 'Invite reward');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSpendDialog() async {
    final controller = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Spend coins'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Amount'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a valid amount')),
                  );
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Spend'),
            ),
          ],
        );
      },
    );

    if (amount != null) {
      await _handleSpend(amount, 'Manual spend');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet'),
      ),
      body: user == null
          ? const Center(child: Text('Sign in to view wallet'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: _WalletHeader(
                      uid: user.uid,
                      onEarn: _openEarnSheet,
                      onBuy: () {
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(
                          builder: (_) => const CoinsShopPage(),
                        ));
                      },
                      onVip: () {
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(
                          builder: (_) => const VipPage(),
                        ));
                      },
                      onSpend: _showSpendDialog,
                    ),
                  ),
                  if (_error != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  if (_loading && _transactions.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_transactions.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No transactions yet')),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= _transactions.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final tx = _transactions[index];
                          return Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                            child: Card(
                              child: TransactionTile(transaction: tx),
                            ),
                          );
                        },
                        childCount: _transactions.length + (_loadingMore ? 1 : 0),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({
    required this.uid,
    required this.onEarn,
    required this.onBuy,
    required this.onVip,
    required this.onSpend,
  });

  final String uid;
  final VoidCallback onEarn;
  final VoidCallback onBuy;
  final VoidCallback onVip;
  final VoidCallback onSpend;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final docStream = firestore.collection('users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docStream,
      builder: (context, snapshot) {
        final data = (snapshot.data?.data() ?? <String, dynamic>{});
        final coins = (data['coins'] is int)
            ? data['coins'] as int
            : data['coins'] is num
                ? (data['coins'] as num).toInt()
                : 0;
        final vipTier = (data['vipTier'] as String? ?? 'none').toLowerCase();
        final vipSinceRaw = data['vipSince'];
        DateTime? vipSince;
        if (vipSinceRaw is Timestamp) {
          vipSince = vipSinceRaw.toDate();
        } else if (vipSinceRaw is DateTime) {
          vipSince = vipSinceRaw;
        }
        final locale = Localizations.localeOf(context).toLanguageTag();
        final numberFormat = NumberFormat.decimalPattern(locale);
        final sinceText = vipSince != null
            ? DateFormat.yMMMd(locale).format(vipSince.toLocal())
            : null;

        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
          child: Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Coins balance',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      CoinsPill(
                        coins: coins,
                        semanticsLabel:
                            'Coins: ${numberFormat.format(coins)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  VipChip(
                    tier: vipTier,
                    label: 'VIP',
                    noneLabel: 'None',
                    onTap: onVip,
                  ),
                  if (sinceText != null) ...[
                    const SizedBox(height: 4),
                    Text('Since $sinceText',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: onEarn,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Earn coins'),
                      ),
                      FilledButton.icon(
                        onPressed: onBuy,
                        icon: const Icon(Icons.shopping_bag_rounded),
                        label: const Text('Buy coins'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onVip,
                        icon: const Icon(Icons.workspace_premium_rounded),
                        label: const Text('VIP tiers'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onSpend,
                        icon: const Icon(Icons.payments_rounded),
                        label: const Text('Spend coins'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
