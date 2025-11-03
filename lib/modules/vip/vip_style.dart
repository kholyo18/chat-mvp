import 'package:flutter/material.dart';

class VipStyle {
  const VipStyle({
    required this.nameColor,
    this.glowColor,
    required this.entryEffectKey,
    required this.bubbleTheme,
  });

  final Color nameColor;
  final Color? glowColor;
  final String entryEffectKey;
  final String bubbleTheme;

  bool get hasEffect => entryEffectKey != 'none';
}

VipStyle getVipStyle(String? vipTier) {
  final normalized = (vipTier ?? 'none').trim().toLowerCase();
  switch (normalized) {
    case 'gold':
      return const VipStyle(
        nameColor: Color(0xFFFFD700),
        glowColor: Color(0x66FFD700),
        entryEffectKey: 'gold',
        bubbleTheme: 'vip_gold',
      );
    case 'diamond':
      return const VipStyle(
        nameColor: Color(0xFF40E0D0),
        glowColor: Color(0x6640E0D0),
        entryEffectKey: 'diamond',
        bubbleTheme: 'vip_diamond',
      );
    case 'platinum':
    case 'titanium':
      return const VipStyle(
        nameColor: Color(0xFFE5E4E2),
        glowColor: Color(0x66E5E4E2),
        entryEffectKey: 'platinum',
        bubbleTheme: 'vip_platinum',
      );
    case 'bronze':
      return const VipStyle(
        nameColor: Color(0xFFCD7F32),
        glowColor: Color(0x33CD7F32),
        entryEffectKey: 'bronze',
        bubbleTheme: 'vip_bronze',
      );
    case 'silver':
      return const VipStyle(
        nameColor: Color(0xFFC0C0C0),
        glowColor: Color(0x33C0C0C0),
        entryEffectKey: 'silver',
        bubbleTheme: 'vip_silver',
      );
    default:
      return const VipStyle(
        nameColor: Color(0xFF212121),
        glowColor: null,
        entryEffectKey: 'none',
        bubbleTheme: 'default',
      );
  }
}
