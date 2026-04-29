import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbpProvider', () {
    test('id and name are correct', () {
      final provider = NbpProvider();
      expect(provider.id, 'nbp');
      expect(provider.name, 'Narodowy Bank Polski');
      expect(provider.initials, 'NBP');
    });

    test('fetchRates works with live NBP JSON API', () async {
      final provider = NbpProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PLN'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['PLN'], greaterThan(0));
    });
  });
}
