import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RbnzProvider', () {
    test('id and name are correct', () {
      final provider = RbnzProvider();
      expect(provider.id, 'rbnz');
      expect(provider.name, 'Reserve Bank of New Zealand');
      expect(provider.initials, 'RBNZ');
    });

    test('parseRbnzHtml parses rates from sample HTML', () {
      const sampleHtml = '''
<table class="table--data">
    <thead>
        <tr>
            <th></th>
            <th>17 Apr 2026</th>
            <th>01 May 2026</th>
        </tr>
    </thead>
    <tbody>
        <tr><td colspan="3"><strong>TWI</strong></td></tr>
        <tr>
            <td>17 currency basket</td>
            <td>66.58</td>
            <td class="table__cell--bold">66.85</td>
        </tr>
        <tr><td colspan="3"><strong>Selected exchange rates</strong></td></tr>
        <tr>
            <td>United States dollar</td>
            <td>0.58835</td>
            <td class="table__cell--bold">0.59065</td>
        </tr>
        <tr>
            <td>UK pound sterling</td>
            <td>0.43525</td>
            <td class="table__cell--bold">0.43410</td>
        </tr>
        <tr>
            <td>Australian dollar</td>
            <td>0.82145</td>
            <td class="table__cell--bold">0.82005</td>
        </tr>
        <tr>
            <td>Japanese yen</td>
            <td>93.76240</td>
            <td class="table__cell--bold">92.84135</td>
        </tr>
        <tr>
            <td>European euro</td>
            <td>0.49965</td>
            <td class="table__cell--bold">0.50350</td>
        </tr>
        <tr>
            <td>Chinese renminbi</td>
            <td>4.01510</td>
            <td class="table__cell--bold">4.03630</td>
        </tr>
    </tbody>
</table>
''';

      final result = RbnzProvider.parseRbnzHtml(sampleHtml);
      expect(result, isNotNull);
      expect(result, isNotEmpty);
      expect(result!.containsKey('EUR'), isTrue);
      expect(result['EUR'], equals(1.0));

      // Rates are quoted as foreign currency per 1 NZD.
      // After normalizing to EUR base:
      // normalized['USD'] = (1/0.50350) / (1/0.59065) = 0.59065 / 0.50350
      expect(result['USD'], closeTo(0.59065 / 0.50350, 0.0001));
      expect(result['GBP'], closeTo(0.43410 / 0.50350, 0.0001));
      expect(result['AUD'], closeTo(0.82005 / 0.50350, 0.0001));
      expect(result['JPY'], closeTo(92.84135 / 0.50350, 0.001));
      expect(result['CNY'], closeTo(4.03630 / 0.50350, 0.0001));
      expect(result['NZD'], closeTo(1.0 / 0.50350, 0.0001));
    });

    test('fetchRates works with live API', () async {
      final provider = RbnzProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
