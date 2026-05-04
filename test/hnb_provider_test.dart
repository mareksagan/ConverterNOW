import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HnbProvider', () {
    test('id and name are correct', () {
      final provider = HnbProvider();
      expect(provider.id, 'hnb');
      expect(provider.name, 'Croatian National Bank');
      expect(provider.initials, 'HNB');
    });

    test('fetchRates works with live API', () async {
      final provider = HnbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BAM'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['BAM'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
