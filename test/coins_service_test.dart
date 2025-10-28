import 'package:chat_mvp/services/coins_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoinsService', () {
    test('addCoinsDev updates balance (stub)', () {
      final service = CoinsService();
      expect(service, isNotNull);
    }, skip: 'Requires Firestore emulator to validate transactions.');

    test('spend throws when insufficient (stub)', () {
      final service = CoinsService();
      expect(service, isNotNull);
    }, skip: 'Requires Firestore emulator to validate transactions.');
  });
}
