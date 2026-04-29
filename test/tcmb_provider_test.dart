import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TcmbProvider', () {
    test('id and name are correct', () {
      final provider = TcmbProvider();
      expect(provider.id, 'tcmb');
      expect(provider.name, 'Türkiye Cumhuriyet Merkez Bankası');
      expect(provider.initials, 'TCMB');
    });

    test('fetchRates works with live TCMB XML API', () async {
      final provider = TcmbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('TRY'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['TRY'], greaterThan(0));
    });
  });
}
