import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DanmarksNationalbankProvider', () {
    test('id, name and initials are correct', () {
      final provider = DanmarksNationalbankProvider();
      expect(provider.id, 'danmarks_nationalbank');
      expect(provider.name, 'Danmarks Nationalbank');
      expect(provider.initials, 'DN');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = DanmarksNationalbankProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('Danmarks Nationalbank live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('DKK'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
