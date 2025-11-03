import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/store_product.dart';
import '../../screens/store/store_strings.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onBuy,
    required this.onView,
    this.busy = false,
    this.currentVipTier,
  });

  final StoreProduct product;
  final VoidCallback onBuy;
  final VoidCallback onView;
  final bool busy;
  final String? currentVipTier;

  IconData _iconForProduct(String iconName) {
    switch (iconName) {
      case 'theme':
        return Icons.color_lens_rounded;
      case 'vip':
        return Icons.workspace_premium_rounded;
      case 'coins':
        return Icons.monetization_on_rounded;
      case 'feature':
        return Icons.star_rounded;
      case 'boost':
        return Icons.bolt_rounded;
      default:
        return Icons.shopping_bag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    final NumberFormat currencyFmt = (() {
      try {
        return NumberFormat.simpleCurrency(name: product.currency);
      } catch (_) {
        return NumberFormat.simpleCurrency();
      }
    })();

    final priceLabel = currencyFmt.format(product.price);
    final currentTier = (currentVipTier ?? '').trim().toLowerCase();
    final productVipTier = (product.vipTier ?? '').trim().toLowerCase();
    final vipComparison = product.isVipProduct && productVipTier.isNotEmpty
        ? _vipComparisonText(context, currentTier, productVipTier)
        : null;
    final vipBadgeLabel = product.badge.isNotEmpty
        ? product.badge
        : storeTr(context, 'vip_badge_label');
    final vipTierDisplay = productVipTier.isNotEmpty
        ? _titleCase(productVipTier)
        : '';

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                    child: Icon(
                      _iconForProduct(product.icon),
                      size: 28,
                      textDirection: textDirection,
                    ),
                  ),
                  if (product.isVipProduct)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        vipBadgeLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                product.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                product.subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
              ),
              if (product.isVipProduct) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.workspace_premium_rounded, size: 18),
                      label: Text(
                        vipTierDisplay.isEmpty
                            ? storeTr(context, 'vip_badge_label')
                            : vipTierDisplay,
                      ),
                    ),
                    if (vipComparison != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vipComparison,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const Spacer(),
              if (product.type == 'coins' && product.coinsAmount > 0)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(bottom: 4, top: 8),
                  child: Text(
                    storeTr(
                      context,
                      'coins_amount',
                      params: <String, String>{
                        'coins': product.coinsAmount.toString(),
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              Text(
                priceLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onBuy,
                  child: busy
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Text(product.isVipProduct
                          ? storeTr(context, 'buy_vip')
                          : storeTr(context, 'buy')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  int _vipRank(String value) {
    switch (value) {
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

  String? _vipComparisonText(
    BuildContext context,
    String currentTier,
    String productTier,
  ) {
    final productRank = _vipRank(productTier);
    final currentRank = _vipRank(currentTier);
    if (productRank == 0) {
      return null;
    }
    if (currentRank == 0) {
      return storeTr(context, 'vip_comparison_unlock');
    }
    final currentLabel = _titleCase(currentTier);
    if (productRank > currentRank) {
      return storeTr(
        context,
        'vip_comparison_upgrade',
        params: <String, String>{'current': currentLabel},
      );
    }
    if (productRank == currentRank) {
      return storeTr(
        context,
        'vip_comparison_current',
        params: <String, String>{'tier': currentLabel},
      );
    }
    return storeTr(
      context,
      'vip_comparison_higher',
      params: <String, String>{'tier': currentLabel},
    );
  }
}
