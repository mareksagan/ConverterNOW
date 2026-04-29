import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbmProvider', () {
    test('id and name are correct', () {
      final provider = CbmProvider();
      expect(provider.id, 'cbm');
      expect(provider.name, 'Central Bank of Myanmar');
      expect(provider.initials, 'CBM');
    });

    test('fetchRates works with live API', () async {
      final provider = CbmProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('MMK'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['MMK'], greaterThan(0));
    });
  });
}
