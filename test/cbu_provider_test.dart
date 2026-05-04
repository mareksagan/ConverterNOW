import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbuProvider', () {
    test('id and name are correct', () {
      final provider = CbuProvider();
      expect(provider.id, 'cbu');
      expect(provider.name, "O'zbekiston Markaziy Banki");
      expect(provider.initials, 'CBU');
    });

    test('fetchRates works with live CBU JSON API', () async {
      final provider = CbuProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('UZS'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['UZS'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
