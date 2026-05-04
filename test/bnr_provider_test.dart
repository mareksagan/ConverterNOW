import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BnrProvider', () {
    test('id and name are correct', () {
      final provider = BnrProvider();
      expect(provider.id, 'bnr');
      expect(provider.name, 'Banca Națională a României');
      expect(provider.initials, 'BNR');
    });

    test('fetchRates works with live API', () async {
      final provider = BnrProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('RON'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['RON'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
