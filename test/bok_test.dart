import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BokProvider', () {
    test('id and name are correct', () {
      final provider = BokProvider();
      expect(provider.id, 'bok');
      expect(provider.name, 'Bank of Korea');
      expect(provider.initials, 'BOK');
    });

    test('fetchRates works with live API', () async {
      final provider = BokProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('KRW'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['KRW'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
