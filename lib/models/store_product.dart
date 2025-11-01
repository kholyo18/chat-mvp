import 'package:cloud_firestore/cloud_firestore.dart';

class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceCents,
    required this.currency,
    required this.stripePriceId,
    required this.icon,
    required this.active,
    required this.type,
    required this.vipTier,
    required this.coinsAmount,
    required this.sort,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final int priceCents;
  final String currency;
  final String stripePriceId;
  final String icon;
  final bool active;
  final String type;
  final String? vipTier;
  final int coinsAmount;
  final int sort;
  final String? description;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get includesVip => type == 'vip' && (vipTier != null && vipTier!.isNotEmpty);

  double get price => priceCents / 100.0;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'price_cents': priceCents,
      'currency': currency,
      'stripe_price_id': stripePriceId,
      'icon': icon,
      'active': active,
      'type': type,
      'vip_tier': vipTier,
      'coins_amount': coinsAmount,
      'sort': sort,
      'description': description,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory StoreProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return StoreProduct.fromJson(doc.id, data);
  }

  factory StoreProduct.fromJson(String id, Map<String, dynamic> data) {
    return StoreProduct(
      id: id,
      title: (data['title'] as String? ?? '').trim(),
      subtitle: (data['subtitle'] as String? ?? '').trim(),
      priceCents: (data['price_cents'] as num? ?? 0).toInt(),
      currency: (data['currency'] as String? ?? 'USD').toUpperCase(),
      stripePriceId: (data['stripe_price_id'] as String? ?? '').trim(),
      icon: (data['icon'] as String? ?? 'shopping_cart').trim(),
      active: data['active'] == true,
      type: (data['type'] as String? ?? '').trim(),
      vipTier: (data['vip_tier'] as String?)?.trim(),
      coinsAmount: (data['coins_amount'] as num? ?? 0).toInt(),
      sort: (data['sort'] as num? ?? 0).toInt(),
      description: (data['description'] as String?)?.trim(),
      createdAt: data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null,
      updatedAt: data['updatedAt'] is Timestamp ? data['updatedAt'] as Timestamp : null,
    );
  }
}
