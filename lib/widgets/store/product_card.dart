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
  });

  final StoreProduct product;
  final VoidCallback onBuy;
  final VoidCallback onView;
  final bool busy;

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
    final NumberFormat formatter;
    try {
      formatter = NumberFormat.simpleCurrency(name: product.currency);
    } catch (_) {
      formatter = NumberFormat.simpleCurrency();
    }

    final priceLabel = formatter.format(product.price);

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
                  if (product.includesVip)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        storeTr(context, 'includes_vip'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSecondaryContainer,
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
                      : Text(storeTr(context, 'buy')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
