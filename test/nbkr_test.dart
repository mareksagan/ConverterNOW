import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbkrProvider', () {
    test('id and name are correct', () {
      final provider = NbkrProvider();
      expect(provider.id, 'nbkr');
      expect(provider.name, 'National Bank of the Kyrgyz Republic');
      expect(provider.initials, 'NBKR');
    });

    test('fetchRates works with live API', () async {
      final provider = NbkrProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('KGS'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['KGS'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
