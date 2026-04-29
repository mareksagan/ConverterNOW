import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbbProvider', () {
    test('id and name are correct', () {
      final provider = CbbProvider();
      expect(provider.id, 'cbb');
      expect(provider.name, 'Central Bank of Bahrain');
      expect(provider.initials, 'CBB');
    });

    test('fetchRates works with live API', () async {
      final provider = CbbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BHD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['BHD'], greaterThan(0));
    });
  });
}
