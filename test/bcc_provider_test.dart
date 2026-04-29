import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BccProvider', () {
    test('id and name are correct', () {
      final provider = BccProvider();
      expect(provider.id, 'bcc');
      expect(provider.name, 'Banco Central de Cuba');
      expect(provider.initials, 'BCC');
    });

    test('fetchRates works with live BCC JSON API', () async {
      final provider = BccProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CUP'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['CUP'], greaterThan(0));
    });
  });
}
