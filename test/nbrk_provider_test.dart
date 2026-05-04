import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbrkProvider', () {
    test('id and name are correct', () {
      final provider = NbrkProvider();
      expect(provider.id, 'nbrk');
      expect(provider.name, 'National Bank of Republic Kazakhstan');
      expect(provider.initials, 'NBRK');
    });

    test('fetchRates works with live NBRK RSS API', () async {
      final provider = NbrkProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('KZT'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['KZT'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
