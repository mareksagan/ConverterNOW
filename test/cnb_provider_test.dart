import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CnbProvider', () {
    test('id and name are correct', () {
      final provider = CnbProvider();
      expect(provider.id, 'cnb');
      expect(provider.name, 'Česká národní banka');
      expect(provider.initials, 'CNB');
    });

    test('fetchRates works with live CNB JSON API', () async {
      final provider = CnbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CZK'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['CZK'], greaterThan(0));
    });
  });
}
