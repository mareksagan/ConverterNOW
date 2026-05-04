import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RbvProvider', () {
    test('id, name and initials are correct', () {
      final provider = RbvProvider();
      expect(provider.id, 'rbv');
      expect(provider.name, 'Reserve Bank of Vanuatu');
      expect(provider.initials, 'RBV');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = RbvProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('RBV live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('VUV'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
