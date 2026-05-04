import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EestiPankProvider', () {
    test('id and name are correct', () {
      final provider = EestiPankProvider();
      expect(provider.id, 'eesti_pank');
      expect(provider.name, 'Eesti Pank');
      expect(provider.initials, 'EP');
    });

    test('fetchRates works with live API', () async {
      final provider = EestiPankProvider();
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
