import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = r'''
<table>
<thead>
<tr>
<th colspan="5">A. USD/BDT Exchange Rate</th>
</tr>
<tr>
<th>Currency</th>
<th>Bid Rate</th>
<th>Ask Rate</th>
<th>WAR</th>
</tr>
</thead>
<tbody>
<tr><td>USD</td><td>122.7500</td>
    <td>122.7500</td>
    <td>122.7500</td></tr>
</tbody>
</table>

<table>
<thead>
<tr>
<th colspan="3">B. Cross Rates</th>
</tr>
<tr>
<th>Currency</th>
<th>Bid Rate</th>
<th>Ask Rate</th>
</tr>
</thead>
<tbody>
<tr><td>EUR</td><td>143.8630</td><td>143.8875</td></tr>
<tr><td>GBP</td><td>166.5963</td><td>166.6822</td></tr>
<tr><td>AUD</td><td>88.4168</td><td>88.4782</td></tr>
<tr><td>JPY</td><td>0.7814</td><td>0.7817</td></tr>
<tr><td>CAD</td><td>90.3304</td><td>90.3371</td></tr>
<tr><td>SEK</td><td>13.2902</td><td>13.3527</td></tr>
<tr><td>SGD</td><td>96.3576</td><td>96.4030</td></tr>
<tr><td>CNH</td><td>17.9690</td><td>17.9743</td></tr>
<tr><td>INR</td><td>1.2932</td><td>1.2936</td></tr>
<tr><td>LKR</td><td>2.6004</td><td>2.6069</td></tr>
</tbody>
</table>
''';

void main() {
  group('BangladeshBankProvider', () {
    test('id, name and initials are correct', () {
      final p = BangladeshBankProvider();
      expect(p.id, 'bangladesh_bank');
      expect(p.name, 'Bangladesh Bank');
      expect(p.initials, 'BB');
    });

    test('parseBangladeshBankHtml computes mid rates', () {
      final rates = BangladeshBankProvider.parseBangladeshBankHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(1.0, 0.0001));
      // EUR mid = (143.8630 + 143.8875) / 2 = 143.87525
      // USD mid = (122.7500 + 122.7500) / 2 = 122.7500
      // USD normalized = 143.87525 / 122.7500 ≈ 1.1721
      expect(rates['USD'], closeTo(1.1721, 0.0001));
      // BDT normalized = 143.87525 / 1.0 = 143.87525
      expect(rates['BDT'], closeTo(143.8753, 0.0001));
      // GBP mid = (166.5963 + 166.6822) / 2 = 166.63925
      // GBP normalized = 143.87525 / 166.63925 ≈ 0.8634
      expect(rates['GBP'], closeTo(0.8634, 0.0001));
    });

    test('parseBangladeshBankHtml maps CNH to CNY', () {
      final rates = BangladeshBankProvider.parseBangladeshBankHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!.containsKey('CNH'), isFalse);
      expect(rates.containsKey('CNY'), isTrue);
      // CNH mid = (17.9690 + 17.9743) / 2 = 17.97165
      // CNY normalized = 143.87525 / 17.97165 ≈ 8.0057
      expect(rates['CNY'], closeTo(8.0057, 0.0001));
    });

    test('parseBangladeshBankHtml returns null for missing EUR', () {
      final html = _sampleHtml.replaceAll('EUR', 'XXX');
      expect(BangladeshBankProvider.parseBangladeshBankHtml(html), isNull);
    });

    test('parseBangladeshBankHtml returns null for empty tables', () {
      expect(
        BangladeshBankProvider.parseBangladeshBankHtml('<html></html>'),
        isNull,
      );
    });

    test('fetchRates returns EUR-based rates or null', () async {
      final rates = await BangladeshBankProvider().fetchRates();
      if (rates == null) {
        print('Bangladesh Bank live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BDT'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
