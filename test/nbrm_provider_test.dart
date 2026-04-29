import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbrmProvider', () {
    test('id and name are correct', () {
      final provider = NbrmProvider();
      expect(provider.id, 'nbrm');
      expect(provider.name, 'National Bank of Republic Macedonia');
      expect(provider.initials, 'NBRM');
    });

    test('fetchRates works with live API', () async {
      final provider = NbrmProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('MKD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['MKD'], greaterThan(0));
    });
  });
}
