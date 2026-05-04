import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CBSI', () {
    const sampleHtml = r'''
<!DOCTYPE html>
<html>
<body>
<table id="tablepress-2" class="tablepress tablepress-id-2">
<thead>
<tr class="row-1">
  <th class="column-1">Per SBD</th><th class="column-2">Today 30/04/26</th><th class="column-3">Last Week 23/04/26</th>
</tr>
</thead>
<tbody>
<tr class="row-2">
  <td class="column-1"><img src="USD.gif" /> USD</td><td class="column-2">0.1243</td><td class="column-3">0.1243</td>
</tr>
<tr class="row-3">
  <td class="column-1"><img src="GBP.gif" /> GBP</td><td class="column-2">0.0920</td><td class="column-3">0.0920</td>
</tr>
<tr class="row-4">
  <td class="column-1"><img src="EUR.gif" /> EUR</td><td class="column-2">0.1062</td><td class="column-3">0.1062</td>
</tr>
<tr class="row-5">
  <td class="column-1"><img src="AUD.gif" /> AUD</td><td class="column-2">0.1735</td><td class="column-3">0.1737</td>
</tr>
<tr class="row-6">
  <td class="column-1"><img src="NZD.gif" /> NZD</td><td class="column-2">0.2118</td><td class="column-3">0.2104</td>
</tr>
<tr class="row-7">
  <td class="column-1"><img src="JPY.gif" /> JPY</td><td class="column-2">19.86</td><td class="column-3">19.82</td>
</tr>
<tr class="row-8">
  <td class="column-1"><img src="SDR.png" /> SDR</td><td class="column-2">0.0907</td><td class="column-3">0.0906</td>
</tr>
<tr class="row-9">
  <td class="column-1"><img src="CNY.gif" /> CNY</td><td class="column-2">0.8500</td><td class="column-3">0.8487</td>
</tr>
<tr class="row-10">
  <td class="column-1">Index</td><td class="column-2">109.40</td><td class="column-3">109.30</td>
</tr>
</tbody>
</table>
</body>
</html>
''';

    test('parseCbsiHtml extracts and inverts seven currencies, skips SDR/Index', () {
      final rates = CbsiProvider.parseCbsiHtml(sampleHtml);
      expect(rates, isNotNull);

      // Rates are inverted: 1 / foreign-per-SBD
      expect(rates!['USD'], closeTo(1.0 / 0.1243, 0.0001));
      expect(rates['GBP'], closeTo(1.0 / 0.0920, 0.0001));
      expect(rates['EUR'], closeTo(1.0 / 0.1062, 0.0001));
      expect(rates['AUD'], closeTo(1.0 / 0.1735, 0.0001));
      expect(rates['NZD'], closeTo(1.0 / 0.2118, 0.0001));
      expect(rates['JPY'], closeTo(1.0 / 19.86, 0.0001));
      expect(rates['CNY'], closeTo(1.0 / 0.8500, 0.0001));

      // SDR and Index should be skipped
      expect(rates.containsKey('SDR'), isFalse);
      expect(rates.containsKey('Index'), isFalse);
    });

    test('parseCbsiHtml returns null when table is missing', () {
      final rates = CbsiProvider.parseCbsiHtml('<html><body>no data</body></html>');
      expect(rates, isNull);
    });

    test('Provider live test fetchRates returns rates with EUR present', () async {
      final rates = await CbsiProvider().fetchRates();
      if (rates != null) {
        expect(rates['EUR'], isNotNull);
        print('CBSI live rates count: ${rates.length}');
      } else {
        print('CBSI live test returned null (expected in some environments)');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
