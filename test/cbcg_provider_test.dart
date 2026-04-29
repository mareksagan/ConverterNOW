import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbcgProvider', () {
    test('id and name are correct', () {
      final provider = CbcgProvider();
      expect(provider.id, 'cbcg');
      expect(provider.name, 'Central Bank of Montenegro');
      expect(provider.initials, 'CBCG');
    });

    test('fetchRates works with live API', () async {
      final provider = CbcgProvider();
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
