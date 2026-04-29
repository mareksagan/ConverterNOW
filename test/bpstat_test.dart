import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BpstatProvider', () {
    test('id and name are correct', () {
      final provider = BpstatProvider();
      expect(provider.id, 'bpstat');
      expect(provider.name, 'Banco de Portugal');
      expect(provider.initials, 'BP');
    });

    test('fetchRates works with live API', () async {
      final provider = BpstatProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['GBP'], greaterThan(0));
    });
  });
}
