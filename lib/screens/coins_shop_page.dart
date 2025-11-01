import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/wallet_service.dart';

class CoinsShopPage extends StatefulWidget {
  const CoinsShopPage({super.key});

  @override
  State<CoinsShopPage> createState() => _CoinsShopPageState();
}

class _CoinsShopPageState extends State<CoinsShopPage> {
  final WalletService _walletService = WalletService();
  bool _processing = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  static const List<_CoinPack> _packs = <_CoinPack>[
    _CoinPack(id: 'pack_100', coins: 100, priceLabel: '1.99 USD'),
    _CoinPack(id: 'pack_500', coins: 500, priceLabel: '7.99 USD'),
    _CoinPack(id: 'pack_1000', coins: 1000, priceLabel: '14.99 USD'),
  ];

  Future<void> _purchase(_CoinPack pack) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required')),
      );
      return;
    }
    setState(() {
      _processing = true;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await _walletService.earn(
        pack.coins,
        uid: _currentUser!.uid,
        note: 'Coin pack ${pack.coins}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${pack.coins} coins')),
      );
    } on WalletServiceException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final numberFormat = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coins shop'),
      ),
      body: user == null
          ? const Center(child: Text('Sign in to continue'))
          : ListView.builder(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
              itemCount: _packs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return StreamBuilder<int>(
                    stream: _walletService.coinsStream(user.uid),
                    builder: (context, snapshot) {
                      final coins = snapshot.data ?? 0;
                      return Card(
                        margin: const EdgeInsetsDirectional.only(bottom: 16),
                        child: ListTile(
                          leading: const Icon(Icons.account_balance_wallet_rounded),
                          title: const Text('Current balance'),
                          subtitle: Text('${numberFormat.format(coins)} coins'),
                        ),
                      );
                    },
                  );
                }

                final pack = _packs[index - 1];
                return Card(
                  margin: const EdgeInsetsDirectional.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(numberFormat.format(pack.coins)),
                    ),
                    title: Text('${pack.coins} coins'),
                    subtitle: Text(pack.priceLabel),
                    trailing: FilledButton(
                      onPressed: _processing ? null : () => _purchase(pack),
                      child: _processing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Buy'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _CoinPack {
  const _CoinPack({
    required this.id,
    required this.coins,
    required this.priceLabel,
  });

  final String id;
  final int coins;
  final String priceLabel;
}
