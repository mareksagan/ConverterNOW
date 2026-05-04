import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BcvProvider', () {
    test('id, name and initials are correct', () {
      final provider = BcvProvider();
      expect(provider.id, 'bcv');
      expect(provider.name, 'Bank of Cape Verde');
      expect(provider.initials, 'BCV');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BcvProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('BCV live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CVE'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
