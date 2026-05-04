import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BOA', () {
    const sampleHtml = r'''
<!DOCTYPE html>
<html>
<body>
<TABLE border="1">
<thead>
  <TR>
    <th colspan="3">Main Currency</th>
    <th class="text-right" colspan="2">Albanian Lek per  Foreign Currency Unit</th>
  </TR>
</thead>
<TR>
  <TD nowrap>US Dollar</TD>
  <TD nowrap>USD</TD>
  <td align="right" nowrap>81.76</td>
  <td align="right" nowrap>+0.13</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
<TR>
  <TD nowrap>Euro</TD>
  <TD nowrap>EUR</TD>
  <td align="right" nowrap>95.53</td>
  <td align="right" nowrap>-0.02</td>
  <td align="center"><i class="fa fa-arrow-down"></i></td>
</TR>
<TR>
  <TD nowrap>Great Britain Pound</TD>
  <TD nowrap>GBP</TD>
  <td align="right" nowrap>110.31</td>
  <td align="right" nowrap>+0.11</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
<TR>
  <TD nowrap>Japanese Yen   (100)</TD>
  <TD nowrap>JPY</TD>
  <td align="right" nowrap>51.31</td>
  <td align="right" nowrap>+0.21</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
<TR>
  <TD nowrap>Special Drawing Rights</TD>
  <TD nowrap>SDR</TD>
  <td align="right" nowrap>112.01</td>
  <td align="right" nowrap>+0.23</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
<TR>
  <TD nowrap>Gold(OZ 1)</TD>
  <TD nowrap>XAU</TD>
  <td align="right" nowrap>378246.29</td>
  <td align="right" nowrap>+5,622.48</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
<TR>
  <TD nowrap>Chinese Yuan (onshore)</TD>
  <TD nowrap>CNY</TD>
  <td align="right" nowrap>11.97</td>
  <td align="right" nowrap>+0.02</td>
  <td align="center"><i class="fa fa-arrow-up"></i></td>
</TR>
</TABLE>
<TABLE border="1">
<thead>
  <TR>
    <th colspan="3">Currency</th>
    <th class="text-right" colspan="2">Albanian Lek per  Foreign Currency Unit</th>
  </TR>
</thead>
<TR>
  <TD nowrap>Hungarian Forint</TD>
  <TD nowrap>HUF</TD>
  <td align="right" nowrap>26.15</td>
  <td align="right" nowrap>-0.18</td>
  <td align="center"><i class="fa fa-arrow-down"></i></td>
</TR>
<TR>
  <TD nowrap>Czech Koruna</TD>
  <TD nowrap>CZK</TD>
  <td align="right" nowrap>3.92</td>
  <td align="right" nowrap>-0.01</td>
  <td align="center"><i class="fa fa-arrow-down"></i></td>
</TR>
</TABLE>
</body>
</html>
''';

    test('parseBoaHtml extracts rates, adjusts JPY per 100, skips metals/SDR', () {
      final rates = BoaProvider.parseBoaHtml(sampleHtml);
      expect(rates, isNotNull);

      // Rates are ALL per foreign unit — no inversion needed
      expect(rates!['USD'], closeTo(81.76, 0.01));
      expect(rates['EUR'], closeTo(95.53, 0.01));
      expect(rates['GBP'], closeTo(110.31, 0.01));
      expect(rates['JPY'], closeTo(0.5131, 0.0001)); // 51.31 / 100
      expect(rates['CNY'], closeTo(11.97, 0.01));
      expect(rates['HUF'], closeTo(26.15, 0.01));
      expect(rates['CZK'], closeTo(3.92, 0.01));

      // SDR, XAU should be skipped
      expect(rates.containsKey('SDR'), isFalse);
      expect(rates.containsKey('XAU'), isFalse);
    });

    test('parseBoaHtml returns null when table is missing', () {
      final rates = BoaProvider.parseBoaHtml('<html><body>no data</body></html>');
      expect(rates, isNull);
    });

    test('Provider live test fetchRates returns rates with EUR present', () async {
      final rates = await BoaProvider().fetchRates();
      if (rates != null) {
        expect(rates['EUR'], isNotNull);
        print('BOA live rates count: ${rates.length}');
      } else {
        print('BOA live test returned null (expected in some environments)');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
