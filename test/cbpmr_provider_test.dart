import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbpmrProvider', () {
    test('id, name and initials are correct', () {
      final provider = CbpmrProvider();
      expect(provider.id, 'cbpmr');
      expect(provider.name, 'Central Bank of the Republic of Transnistria');
      expect(provider.initials, 'CBPMR');
    });

    test('parseCbpmrCsv returns normalized rates', () {
      const sampleCsv = 'EUR,1,19.3500,0\nUSD,1,17.1500,0\nRUB,100,20.5000,0\n';
      final rates = CbpmrProvider.parseCbpmrCsv(sampleCsv);

      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('RUB'), isTrue);
      expect(rates.containsKey('PRB'), isTrue);

      // EUR=19.35, USD=17.15 => normalized USD = 19.35/17.15
      expect(rates['USD'], closeTo(19.35 / 17.15, 0.0001));
      // EUR=19.35, RUB=0.205 => normalized RUB = 19.35/0.205
      expect(rates['RUB'], closeTo(19.35 / 0.205, 0.0001));
    });

    test('parseCbpmrCsv returns null when EUR is missing', () {
      const csv = 'USD,1,17.1500,0\n';
      expect(CbpmrProvider.parseCbpmrCsv(csv), isNull);
    });

    test('parseCbpmrCsv returns null for empty csv', () {
      expect(CbpmrProvider.parseCbpmrCsv(''), isNull);
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = CbpmrProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('CBPMR live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PRB'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
