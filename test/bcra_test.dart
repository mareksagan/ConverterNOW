import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BcraProvider', () {
    test('id and name are correct', () {
      final provider = BcraProvider();
      expect(provider.id, 'bcra');
      expect(provider.name, 'Banco Central de la República Argentina');
      expect(provider.initials, 'BCRA');
    });

    test('fetchRates works with live API', () async {
      final provider = BcraProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ARS'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ARS'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
