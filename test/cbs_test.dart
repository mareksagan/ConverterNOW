import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsProvider', () {
    test('id and name are correct', () {
      final provider = CbsProvider();
      expect(provider.id, 'cbs');
      expect(provider.name, 'Central Bank of Seychelles');
      expect(provider.initials, 'CBS');
    });

    test('fetchRates works with live API', () async {
      final provider = CbsProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('SCR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['SCR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
