import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BcrpProvider', () {
    test('id and name are correct', () {
      final provider = BcrpProvider();
      expect(provider.id, 'bcrp');
      expect(provider.name, 'Central Reserve Bank of Peru');
      expect(provider.initials, 'BCRP');
    });

    test('fetchRates works with live API', () async {
      final provider = BcrpProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PEN'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['PEN'], greaterThan(0));
    });
  });
}
