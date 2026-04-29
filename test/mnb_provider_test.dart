import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MnbProvider', () {
    test('id and name are correct', () {
      final provider = MnbProvider();
      expect(provider.id, 'mnb');
      expect(provider.name, 'Magyar Nemzeti Bank');
      expect(provider.initials, 'MNB');
    });

    test('fetchRates works with live MNB SOAP API', () async {
      final provider = MnbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('HUF'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['HUF'], greaterThan(0));
    });
  });
}
