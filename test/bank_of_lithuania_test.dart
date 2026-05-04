import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BankOfLithuaniaProvider', () {
    test('id and name are correct', () {
      final provider = BankOfLithuaniaProvider();
      expect(provider.id, 'bank_of_lithuania');
      expect(provider.name, 'Bank of Lithuania');
      expect(provider.initials, 'LB');
    });

    test('fetchRates works with live API', () async {
      final provider = BankOfLithuaniaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('JPY'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['JPY'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
