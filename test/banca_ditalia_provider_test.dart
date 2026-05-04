import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BancaDItaliaProvider', () {
    test('id and name are correct', () {
      final provider = BancaDItaliaProvider();
      expect(provider.id, 'banca_ditalia');
      expect(provider.name, "Banca d'Italia");
      expect(provider.initials, 'BI');
    });

    test('fetchRates works with live API', () async {
      final provider = BancaDItaliaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates['USD'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
