import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HkmaProvider', () {
    test('id and name are correct', () {
      final provider = HkmaProvider();
      expect(provider.id, 'hkma');
      expect(provider.name, 'Hong Kong Monetary Authority');
      expect(provider.initials, 'HKMA');
    });

    test('fetchRates works with live API', () async {
      final provider = HkmaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('HKD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['HKD'], greaterThan(0));
    });
  });
}
