import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoiProvider', () {
    test('id and name are correct', () {
      final provider = BoiProvider();
      expect(provider.id, 'boi');
      expect(provider.name, 'Bank of Israel');
      expect(provider.initials, 'BOI');
    });

    test('fetchRates works with live BOI JSON API', () async {
      final provider = BoiProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ILS'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ILS'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
