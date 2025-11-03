import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

class CheckoutService {
  CheckoutService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> startCheckout(String productId) async {
    final callable = _functions.httpsCallable('createCheckoutSession');
    final response = await callable.call(<String, dynamic>{
      'productId': productId,
      'quantity': 1,
    });
    final data = response.data;
    String? urlString;
    if (data is Map) {
      final rawUrl = data['url'];
      if (rawUrl != null) {
        urlString = rawUrl.toString();
      }
    }
    if (urlString == null || urlString.isEmpty) {
      throw Exception('Missing checkout url');
    }
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Cannot open checkout.');
      }
    } else {
      throw Exception('Cannot open checkout.');
    }
  }
}
