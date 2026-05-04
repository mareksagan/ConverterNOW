import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CentralBankOfIcelandProvider', () {
    test('id and name are correct', () {
      final provider = CentralBankOfIcelandProvider();
      expect(provider.id, 'central_bank_of_iceland');
      expect(provider.name, 'Central Bank of Iceland');
      expect(provider.initials, 'CBI');
    });

    test('fetchRates works with live API', () async {
      final provider = CentralBankOfIcelandProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ISK'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ISK'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
