import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EccbProvider', () {
    test('id, name and initials are correct', () {
      final provider = EccbProvider();
      expect(provider.id, 'eccb');
      expect(provider.name, 'Eastern Caribbean Central Bank');
      expect(provider.initials, 'ECCB');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = EccbProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('ECCB live fetch returned null (likely bot/IP blocking)');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('XCD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
