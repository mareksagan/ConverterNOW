import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BiIndonesiaProvider', () {
    test('id and name are correct', () {
      final provider = BiIndonesiaProvider();
      expect(provider.id, 'bi_indonesia');
      expect(provider.name, 'Bank Indonesia');
      expect(provider.initials, 'BI');
    });

    test('fetchRates works with live API', () async {
      final provider = BiIndonesiaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('IDR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['IDR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
