import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbaProvider', () {
    test('id and name are correct', () {
      final provider = CbaProvider();
      expect(provider.id, 'cba');
      expect(provider.name, 'Central Bank of Armenia');
      expect(provider.initials, 'CBA');
    });

    test('fetchRates works with live CBA SOAP API', () async {
      final provider = CbaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('AMD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['AMD'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
