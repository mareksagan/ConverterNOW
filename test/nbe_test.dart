import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbeProvider', () {
    test('id and name are correct', () {
      final provider = NbeProvider();
      expect(provider.id, 'nbe');
      expect(provider.name, 'National Bank of Ethiopia');
      expect(provider.initials, 'NBE');
    });

    test('fetchRates works with live API', () async {
      final provider = NbeProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ETB'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ETB'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
