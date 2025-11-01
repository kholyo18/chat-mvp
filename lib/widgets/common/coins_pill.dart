import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CoinsPill extends StatelessWidget {
  const CoinsPill({
    super.key,
    required this.coins,
    this.onTap,
    this.semanticsLabel,
  });

  final int coins;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = Directionality.of(context);
    final numberFormatter = NumberFormat.decimalPattern();
    final formattedCoins = numberFormatter.format(coins);
    final effectiveLabel = semanticsLabel ?? 'Coins: $formattedCoins';
    final surface = theme.colorScheme.surfaceVariant;
    final outline = theme.colorScheme.outline.withOpacity(0.3);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: surface.withOpacity(theme.brightness == Brightness.dark ? 0.5 : 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: direction,
        children: [
          Icon(
            Icons.monetization_on_rounded,
            size: 18,
            color: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 6),
          Text(
            formattedCoins,
            style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ) ??
                const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    Widget pill = content;
    if (onTap != null) {
      pill = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: content,
        ),
      );
    }

    return Tooltip(
      message: effectiveLabel,
      child: Semantics(
        label: effectiveLabel,
        button: onTap != null,
        child: pill,
      ),
    );
  }
}
