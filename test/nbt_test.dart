import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbtProvider', () {
    test('id and name are correct', () {
      final provider = NbtProvider();
      expect(provider.id, 'nbt');
      expect(provider.name, 'National Bank of Tajikistan');
      expect(provider.initials, 'NBT');
    });

    test('fetchRates works with live API', () async {
      final provider = NbtProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('TJS'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['TJS'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
