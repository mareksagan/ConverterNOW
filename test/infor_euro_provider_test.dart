import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InforEuroProvider', () {
    test('id, name and initials are correct', () {
      final provider = InforEuroProvider();
      expect(provider.id, 'inforeuro');
      expect(provider.name, 'InforEuro');
      expect(provider.initials, 'IE');
    });

    test('fetchRates returns EUR-based rates', () async {
      final provider = InforEuroProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('InforEuro live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
