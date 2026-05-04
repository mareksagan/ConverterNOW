import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NRBT', () {
    const sampleHtml = r'''
<!DOCTYPE html>
<html>
<body>
<table class="table-custom-4c" border="1">
<thead>
<tr>
<td>Selected Exchange Rates</td>
<td style="text-align: center;">BUY</td>
<td style="text-align: center;">MID</td>
<td style="text-align: center;">SELL</td>
</tr>
</thead>
<tbody>
<tr>
<td>Australian Dollar</td>
<td style="text-align: center;">0.6095</td>
<td style="text-align: center;">0.5975</td>
<td style="text-align: center;">0.5855</td>
</tr>
<tr>
<td>European Euro</td>
<td style="text-align: center;">0.3805</td>
<td style="text-align: center;">0.3603</td>
<td style="text-align: center;">0.3400</td>
</tr>
<tr>
<td>Fijian Dollar</td>
<td style="text-align: center;">0.9436</td>
<td style="text-align: center;">0.9235</td>
<td style="text-align: center;">0.9033</td>
</tr>
<tr>
<td>British Pound</td>
<td style="text-align: center;">0.3252</td>
<td style="text-align: center;">0.3118</td>
<td style="text-align: center;">0.2985</td>
</tr>
<tr>
<td>Japanese Yen</td>
<td style="text-align: center;">68.877</td>
<td style="text-align: center;">67.5868</td>
<td style="text-align: center;">66.3030</td>
</tr>
<tr>
<td>New Zealand Dollar</td>
<td style="text-align: center;">0.7373</td>
<td style="text-align: center;">0.7219</td>
<td style="text-align: center;">0.7066</td>
</tr>
<tr>
<td>United States Dollar</td>
<td style="text-align: center;">0.4298</td>
<td style="text-align: center;">0.4222</td>
<td style="text-align: center;">0.4145</td>
</tr>
<tr>
<td>Samoan Tala</td>
<td style="text-align: center;">1.2639</td>
<td style="text-align: center;">1.1441</td>
<td style="text-align: center;">1.0243</td>
</tr>
<tr>
<td>Switzerland Francs</td>
<td style="text-align: center;">0.3464</td>
<td style="text-align: center;">0.3314</td>
<td style="text-align: center;">0.3164</td>
</tr>
<tr>
<td>Canada Dollar</td>
<td style="text-align: center;">0.5959</td>
<td style="text-align: center;">0.5766</td>
<td style="text-align: center;">0.5573</td>
</tr>
<tr>
<td>Sweden Kronor</td>
<td style="text-align: center;">4.0553</td>
<td style="text-align: center;">3.9267</td>
<td style="text-align: center;">3.7982</td>
</tr>
<tr>
<td>Singapore Dollar</td>
<td style="text-align: center;">0.5666</td>
<td style="text-align: center;">0.5438</td>
<td style="text-align: center;">0.5211</td>
</tr>
</tbody>
</table>
</body>
</html>
''';

    test('parseNrbtHtml extracts and inverts twelve currencies using MID', () {
      final rates = NrbtProvider.parseNrbtHtml(sampleHtml);
      expect(rates, isNotNull);

      // Rates are inverted: 1 / foreign-per-TOP (using MID)
      expect(rates!['AUD'], closeTo(1.0 / 0.5975, 0.0001));
      expect(rates['EUR'], closeTo(1.0 / 0.3603, 0.0001));
      expect(rates['FJD'], closeTo(1.0 / 0.9235, 0.0001));
      expect(rates['GBP'], closeTo(1.0 / 0.3118, 0.0001));
      expect(rates['JPY'], closeTo(1.0 / 67.5868, 0.0001));
      expect(rates['NZD'], closeTo(1.0 / 0.7219, 0.0001));
      expect(rates['USD'], closeTo(1.0 / 0.4222, 0.0001));
      expect(rates['WST'], closeTo(1.0 / 1.1441, 0.0001));
      expect(rates['CHF'], closeTo(1.0 / 0.3314, 0.0001));
      expect(rates['CAD'], closeTo(1.0 / 0.5766, 0.0001));
      expect(rates['SEK'], closeTo(1.0 / 3.9267, 0.0001));
      expect(rates['SGD'], closeTo(1.0 / 0.5438, 0.0001));
    });

    test('parseNrbtHtml returns null when table is missing', () {
      final rates = NrbtProvider.parseNrbtHtml('<html><body>no data</body></html>');
      expect(rates, isNull);
    });

    test('parseNrbtHtml ignores unknown currency names', () {
      const html = '<table><tr><td>Unknown Currency</td><td>1.0</td><td>2.0</td><td>3.0</td></tr></table>';
      final rates = NrbtProvider.parseNrbtHtml(html);
      expect(rates, isNull);
    });

    test('Provider live test fetchRates returns rates with EUR present', () async {
      final rates = await NrbtProvider().fetchRates();
      if (rates != null) {
        expect(rates['EUR'], isNotNull);
        print('NRBT live rates count: ${rates.length}');
      } else {
        print('NRBT live test returned null (expected in some environments)');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
