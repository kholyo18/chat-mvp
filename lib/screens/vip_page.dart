import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/wallet_service.dart';
import '../widgets/common/vip_chip.dart';

class VipPage extends StatefulWidget {
  const VipPage({super.key});

  @override
  State<VipPage> createState() => _VipPageState();
}

class _VipPageState extends State<VipPage> {
  final WalletService _walletService = WalletService();
  bool _processing = false;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  static const List<_VipTierOption> _tiers = <_VipTierOption>[
    _VipTierOption(id: 'bronze', price: 500, perks: 'Bronze badge + profile theme'),
    _VipTierOption(id: 'silver', price: 1500, perks: 'Silver badge + 2x daily bonus'),
    _VipTierOption(id: 'gold', price: 3000, perks: 'Gold badge + priority support'),
    _VipTierOption(id: 'platinum', price: 6000, perks: 'Platinum badge + exclusive rooms'),
  ];

  Future<void> _upgrade(_VipTierOption tier) async {
    final user = _currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in required')),
      );
      return;
    }
    setState(() {
      _processing = true;
    });
    try {
      await _walletService.upgradeVip(
        tier.id,
        price: tier.price,
        uid: user.uid,
        note: 'Upgrade to ${_titleCase(tier.id)}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upgraded to ${_titleCase(tier.id)}')), 
      );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP tiers'),
      ),
      body: user == null
          ? const Center(child: Text('Sign in to continue'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = (snapshot.data?.data() ?? <String, dynamic>{});
                final coins = data['coins'] is int
                    ? data['coins'] as int
                    : data['coins'] is num
                        ? (data['coins'] as num).toInt()
                        : 0;
                final currentTier = (data['vipTier'] as String? ?? 'none').toLowerCase();
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

                return ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
                  itemCount: _tiers.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Card(
                        margin: const EdgeInsetsDirectional.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Current tier',
                                  style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              VipChip(
                                tier: currentTier,
                                label: 'VIP',
                                noneLabel: 'None',
                              ),
                              const SizedBox(height: 8),
                              Text('Balance: ${numberFormat.format(coins)} coins'),
                              if (sinceText != null)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(top: 4),
                                  child: Text('Since $sinceText',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              color: Theme.of(context).colorScheme.outline)),
                                ),
                            ],
                          ),
                        ),
                      );
                    }

                    final tier = _tiers[index - 1];
                    final tierName = _titleCase(tier.id);
                    final isCurrent = tier.id == currentTier;
                    final canUpgrade = _tierRank(tier.id) > _tierRank(currentTier);
                    final hasCoins = coins >= tier.price;
                    return Card(
                      margin: const EdgeInsetsDirectional.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.workspace_premium_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  tierName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Text('${numberFormat.format(tier.price)} coins'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(tier.perks),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: !_processing && canUpgrade && hasCoins
                                  ? () => _upgrade(tier)
                                  : null,
                              child: isCurrent
                                  ? const Text('Current tier')
                                  : canUpgrade
                                      ? const Text('Upgrade')
                                      : const Text('Locked'),
                            ),
                            if (!hasCoins && canUpgrade)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(top: 6),
                                child: Text(
                                  'Need ${numberFormat.format(tier.price - coins)} more coins',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  int _tierRank(String tier) {
    switch (tier) {
      case 'bronze':
        return 1;
      case 'silver':
        return 2;
      case 'gold':
        return 3;
      case 'platinum':
        return 4;
      default:
        return 0;
    }
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _VipTierOption {
  const _VipTierOption({
    required this.id,
    required this.price,
    required this.perks,
  });

  final String id;
  final int price;
  final String perks;
}
