import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NbuProvider', () {
    test('id and name are correct', () {
      final provider = NbuProvider();
      expect(provider.id, 'nbu');
      expect(provider.name, 'National Bank of Ukraine');
      expect(provider.initials, 'NBU');
    });

    test('fetchRates works with live NBU XML API', () async {
      final provider = NbuProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('UAH'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['UAH'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
