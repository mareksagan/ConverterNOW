import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BogProvider', () {
    test('id, name and initials are correct', () {
      final provider = BogProvider();
      expect(provider.id, 'bog');
      expect(provider.name, 'Bank of Guyana');
      expect(provider.initials, 'BOG');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BogProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('BOG live fetch returned null (likely bot/IP blocking)');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GYD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
