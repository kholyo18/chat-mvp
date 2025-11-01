import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/coin_transaction.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.transaction,
    this.numberFormat,
    this.onTap,
  });

  final CoinTransaction transaction;
  final NumberFormat? numberFormat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatter = numberFormat ?? NumberFormat.decimalPattern(locale);
    final dateFormatter = DateFormat.yMMMd(locale).add_jm();
    final amountSign = transaction.amount > 0 ? '+' : '';
    final amountText = '$amountSign${formatter.format(transaction.amount)}';
    final icon = _iconForType(transaction.type);
    final colorScheme = theme.colorScheme;
    final isCredit = transaction.isCredit;
    final amountColor = isCredit
        ? colorScheme.secondary
        : colorScheme.error;
    final subtitleParts = <String>[
      if (transaction.note.isNotEmpty) transaction.note,
      dateFormatter.format(transaction.createdAt.toLocal()),
    ];

    final subtitleText = subtitleParts.join(' • ');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: colorScheme.surfaceVariant.withOpacity(0.6),
        child: Icon(icon, color: colorScheme.primary),
      ),
      title: Text(
        amountText,
        style: theme.textTheme.titleMedium?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
        textDirection: Directionality.of(context),
      ),
      subtitle: Text(
        subtitleText,
        textDirection: Directionality.of(context),
      ),
      trailing: Text(
        formatter.format(transaction.balanceAfter),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.outline,
        ),
        textDirection: Directionality.of(context),
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'earn':
      case 'bonus':
        return Icons.add_circle_rounded;
      case 'spend':
        return Icons.remove_circle_outline;
      case 'vip_upgrade':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.monetization_on_rounded;
    }
  }
}
