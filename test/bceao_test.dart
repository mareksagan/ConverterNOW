import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BceaoProvider', () {
    test('id and name are correct', () {
      final provider = BceaoProvider();
      expect(provider.id, 'bceao');
      expect(provider.name, 'Central Bank of West African States');
      expect(provider.initials, 'BCEAO');
    });

    test('fetchRates works with live API', () async {
      final provider = BceaoProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('XOF'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['XOF'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
