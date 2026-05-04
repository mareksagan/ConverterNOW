import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankNegaraMalaysiaProvider', () {
    test('id and name are correct', () {
      final provider = BankNegaraMalaysiaProvider();
      expect(provider.id, 'bank_negara_malaysia');
      expect(provider.name, 'Bank Negara Malaysia');
      expect(provider.initials, 'BNM');
    });

    test('fetchRates works with live API', () async {
      final provider = BankNegaraMalaysiaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('MYR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['MYR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
