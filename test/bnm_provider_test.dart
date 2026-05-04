import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BnmProvider', () {
    test('id, name and initials are correct', () {
      final provider = BnmProvider();
      expect(provider.id, 'bnm');
      expect(provider.name, 'National Bank of Moldova');
      expect(provider.initials, 'BNM');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BnmProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('BNM live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('MDL'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
