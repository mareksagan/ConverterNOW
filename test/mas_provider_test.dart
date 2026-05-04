import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MasProvider', () {
    test('id, name and initials are correct', () {
      final provider = MasProvider();
      expect(provider.id, 'mas');
      expect(provider.name, 'Monetary Authority of Singapore');
      expect(provider.initials, 'MAS');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = MasProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('MAS live fetch returned null (likely form token expiry)');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('SGD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
