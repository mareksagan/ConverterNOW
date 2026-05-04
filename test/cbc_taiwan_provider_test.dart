import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbcTaiwanProvider', () {
    test('id and name are correct', () {
      final provider = CbcTaiwanProvider();
      expect(provider.id, 'cbc_taiwan');
      expect(provider.name, 'Central Bank of Taiwan');
      expect(provider.initials, 'CBC');
    });

    test('fetchRates works with live API', () async {
      final provider = CbcTaiwanProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('TWD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['TWD'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
