import 'package:flutter/widgets.dart';

const Map<String, Map<String, String>> _kStoreStrings = <String, Map<String, String>>{
  'en': <String, String>{
    'store_title': 'Store',
    'buy': 'Buy',
    'buy_vip': 'Buy VIP',
    'price': 'Price',
    'purchases_title': 'Purchase history',
    'purchase_status_paid': 'Paid',
    'purchase_status_refunded': 'Refunded',
    'retry': 'Retry',
    'failed_to_load_store': 'Failed to load the store. Please try again later.',
    'no_products': 'No products available right now.',
    'view_purchases': 'View purchases',
    'failed_to_start_checkout': 'Unable to open checkout. Please try again.',
    'complete_in_browser': 'Checkout opened in browser. Complete payment to unlock your item.',
    'not_signed_in': 'Please login to access the store.',
    'no_purchases': 'No purchases yet.',
    'failed_to_load_purchases': 'Failed to load purchases. Please try again later.',
    'includes_vip': 'Includes VIP',
    'vip_badge_label': 'VIP',
    'vip_comparison_unlock': 'Unlock your first VIP tier.',
    'vip_comparison_upgrade': 'Upgrade from {current} VIP.',
    'vip_comparison_current': 'You already have {tier} VIP.',
    'vip_comparison_higher': 'You already have a higher VIP tier ({tier}).',
    'coins_amount': '{coins} coins',
    'category_all': 'All',
    'category_coins': 'Coins',
    'category_vip': 'VIP',
    'category_themes': 'Themes',
    'category_subscriptions': 'Subscriptions',
    'coins_resume_message': 'If payment completed, your coins will appear shortly.',
    'vip_resume_message': 'If payment completed, your VIP will activate shortly. Pull to refresh.',
    'refresh': 'Refresh',
    'vip_notice_higher': 'Your account is already at a higher VIP level.',
    'vip_benefits_title': 'VIP benefits',
  },
  'ar': <String, String>{
    'store_title': 'المتجر',
    'buy': 'شراء',
    'buy_vip': 'شراء VIP',
    'price': 'السعر',
    'purchases_title': 'سجل المشتريات',
    'purchase_status_paid': 'مدفوع',
    'purchase_status_refunded': 'مسترد',
    'retry': 'إعادة المحاولة',
    'failed_to_load_store': 'تعذّر تحميل المتجر. حاول مرة أخرى لاحقاً.',
    'no_products': 'لا توجد منتجات حالياً.',
    'view_purchases': 'عرض المشتريات',
    'failed_to_start_checkout': 'تعذّر فتح صفحة الدفع. حاول مرة أخرى.',
    'complete_in_browser': 'تم فتح الدفع في المتصفح. أكمل الدفع للحصول على العنصر.',
    'not_signed_in': 'يرجى تسجيل الدخول للوصول إلى المتجر.',
    'no_purchases': 'لا توجد مشتريات بعد.',
    'failed_to_load_purchases': 'تعذّر تحميل سجل المشتريات. حاول لاحقاً.',
    'includes_vip': 'يتضمن VIP',
    'vip_badge_label': 'VIP',
    'vip_comparison_unlock': 'ابدأ عضويتك المميزة الآن.',
    'vip_comparison_upgrade': 'قم بالترقية من {current} VIP.',
    'vip_comparison_current': 'لديك بالفعل {tier} VIP.',
    'vip_comparison_higher': 'لديك مستوى VIP أعلى ({tier}).',
    'coins_amount': '{coins} عملة',
    'category_all': 'الكل',
    'category_coins': 'العملات',
    'category_vip': 'العضويات المميزة',
    'category_themes': 'الثيمات',
    'category_subscriptions': 'الاشتراكات',
    'coins_resume_message': 'إذا اكتملت عملية الدفع، ستظهر العملات قريباً.',
    'vip_resume_message': 'إذا اكتملت عملية الدفع، سيتم تفعيل VIP قريباً. اسحب للتحديث.',
    'refresh': 'تحديث',
    'vip_notice_higher': 'حسابك مسجّل بالفعل بمستوى VIP أعلى.',
    'vip_benefits_title': 'مزايا VIP',
  },
};

String storeTr(BuildContext context, String key, {Map<String, String> params = const <String, String>{}}) {
  final locale = Localizations.localeOf(context);
  final languageCode = locale.languageCode.toLowerCase();
  final fallback = _kStoreStrings['en'] ?? const <String, String>{};
  final table = _kStoreStrings[languageCode] ?? fallback;
  var value = table[key] ?? fallback[key] ?? key;
  if (params.isNotEmpty) {
    params.forEach((name, replace) {
      value = value.replaceAll('{$name}', replace);
    });
  }
  return value;
}
