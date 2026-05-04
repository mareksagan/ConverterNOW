import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankOfCanadaProvider', () {
    test('id, name and initials are correct', () {
      final provider = BankOfCanadaProvider();
      expect(provider.id, 'bank_of_canada');
      expect(provider.name, 'Bank of Canada');
      expect(provider.initials, 'BOC');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BankOfCanadaProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('Bank of Canada live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CAD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
