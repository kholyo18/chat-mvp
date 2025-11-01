import 'package:flutter/material.dart';

class VipChip extends StatelessWidget {
  const VipChip({
    super.key,
    required this.tier,
    this.label = 'VIP',
    this.noneLabel = 'None',
  });

  final String tier;
  final String label;
  final String noneLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final normalized = tier.trim().toLowerCase();
    final isNeutral = normalized.isEmpty || normalized == 'none';
    final displayTier = isNeutral ? noneLabel : _capitalise(normalized);
    final tone = _colorForTier(scheme, normalized);
    final background = isNeutral
        ? scheme.surfaceVariant.withOpacity(0.7)
        : tone.withOpacity(0.18);
    final borderColor = isNeutral
        ? scheme.outline.withOpacity(0.4)
        : tone.withOpacity(0.45);
    final textColor = isNeutral ? scheme.onSurface.withOpacity(0.8) : tone;
    final textDirection = Directionality.of(context);
    final labelText = '$label: $displayTier';

    final textStyle = theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: textColor,
        ) ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        );

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        labelText,
        style: textStyle,
        textDirection: textDirection,
      ),
    );

    return Tooltip(
      message: labelText,
      child: Semantics(
        label: labelText,
        child: chip,
      ),
    );
  }

  String _capitalise(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  Color _colorForTier(ColorScheme scheme, String normalized) {
    switch (normalized) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return Colors.grey.shade600;
      case 'gold':
        return Colors.amber.shade600;
      case 'platinum':
        return Colors.blueGrey.shade500;
      default:
        return scheme.primary;
    }
  }
}
