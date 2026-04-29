import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbsProvider', () {
    test('id and name are correct', () {
      final provider = NbsProvider();
      expect(provider.id, 'nbs');
      expect(provider.name, 'National Bank of Slovakia');
      expect(provider.initials, 'NBS');
    });

    test('fetchRates works with live API', () async {
      final provider = NbsProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ISK'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ISK'], greaterThan(0));
    });
  });
}
