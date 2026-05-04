import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankRossiiProvider', () {
    test('id, name and initials are correct', () {
      final provider = BankRossiiProvider();
      expect(provider.id, 'bank_rossii');
      expect(provider.name, 'Bank Rossii');
      expect(provider.initials, 'CBR');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BankRossiiProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('Bank Rossii live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('RUB'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
