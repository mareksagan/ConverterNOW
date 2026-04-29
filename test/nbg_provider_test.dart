import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbgProvider', () {
    test('id and name are correct', () {
      final provider = NbgProvider();
      expect(provider.id, 'nbg');
      expect(provider.name, 'National Bank of Georgia');
      expect(provider.initials, 'NBG');
    });

    test('fetchRates works with live NBG JSON API', () async {
      final provider = NbgProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GEL'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['GEL'], greaterThan(0));
    });
  });
}
