import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BcbProvider', () {
    test('id, name and initials are correct', () {
      final provider = BcbProvider();
      expect(provider.id, 'bcb_bolivia');
      expect(provider.name, 'Banco Central de Bolivia');
      expect(provider.initials, 'BCB');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = BcbProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('BCB live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BOB'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
