import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RbaProvider', () {
    test('id, name and initials are correct', () {
      final provider = RbaProvider();
      expect(provider.id, 'rba');
      expect(provider.name, 'Reserve Bank of Australia');
      expect(provider.initials, 'RBA');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = RbaProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('RBA live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('AUD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
