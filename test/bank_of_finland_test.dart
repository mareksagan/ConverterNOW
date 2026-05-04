import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankOfFinlandProvider', () {
    test('id and name are correct', () {
      final provider = BankOfFinlandProvider();
      expect(provider.id, 'bank_of_finland');
      expect(provider.name, 'Bank of Finland');
      expect(provider.initials, 'BOF');
    });

    test('fetchRates works with live API', () async {
      final provider = BankOfFinlandProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['GBP'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
