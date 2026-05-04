import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbkProvider', () {
    test('id and name are correct', () {
      final provider = CbkProvider();
      expect(provider.id, 'cbk');
      expect(provider.name, 'Central Bank of Kenya');
      expect(provider.initials, 'CBK');
    });

    test('fetchRates works with live API', () async {
      final provider = CbkProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('KES'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['KES'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
