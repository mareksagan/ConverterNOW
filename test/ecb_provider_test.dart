import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EcbProvider', () {
    test('id, name and initials are correct', () {
      final provider = EcbProvider();
      expect(provider.id, 'ecb');
      expect(provider.name, 'European Central Bank');
      expect(provider.initials, 'ECB');
    });

    test('fetchRates returns EUR-based rates', () async {
      final provider = EcbProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('ECB live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.isNotEmpty, isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
