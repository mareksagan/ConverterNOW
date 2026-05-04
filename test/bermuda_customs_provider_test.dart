import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = '''
<table>
<tbody>
<tr>
<td><strong>Currency </strong></td>
<td><p><strong>April 2nd - </strong></p><p><strong>April 8th</strong></p></td>
<td><p><strong>April 9th - </strong></p><p><strong>April 15th</strong></p></td>
</tr>
<tr>
<td>U.S. Dollar (USD)</td>
<td>1.0000</td>
<td>1.0000</td>
</tr>
<tr>
<td>British Pound (GBP)</td>
<td>1.3303</td>
<td>1.3476</td>
</tr>
<tr>
<td>Canadian Dollar (CAD)</td>
<td>0.7197</td>
<td>0.7216</td>
</tr>
<tr>
<td>Euro (EUR)</td>
<td>1.1598</td>
<td>1.1706</td>
</tr>
<tr>
<td>Australian Dollar (AUD)</td>
<td>0.6948</td>
<td>0.7064</td>
</tr>
<tr>
<td>Hong Kong Dollar (HKD</td>
<td>0.1276</td>
<td>0.1277</td>
</tr>
<tr>
<td>Jamaican Dollar (JMD)</td>
<td>0.0063</td>
<td>0.0063</td>
</tr>
<tr>
<td>Japanese Yen (JPY)</td>
<td>0.0063</td>
<td>0.0063</td>
</tr>
<tr>
<td>Swiss Franc (CHF)</td>
<td>1.2626</td>
<td>1.2689</td>
</tr>
</tbody>
</table>
''';

void main() {
  group('BermudaCustomsProvider', () {
    test('id, name and initials are correct', () {
      final p = BermudaCustomsProvider();
      expect(p.id, 'bermuda_customs');
      expect(p.name, 'Bermuda Customs');
      expect(p.initials, 'BMD');
    });

    test('parseBermudaCustomsHtml computes rates from first table and column',
        () {
      final rates = BermudaCustomsProvider.parseBermudaCustomsHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(1.0, 0.0001));
      // EUR = 1.1598, USD = 1.0, BMD = 1.0
      // USD normalized = 1.1598 / 1.0 = 1.1598
      expect(rates['USD'], closeTo(1.1598, 0.0001));
      // BMD normalized = 1.1598 / 1.0 = 1.1598
      expect(rates['BMD'], closeTo(1.1598, 0.0001));
      // GBP normalized = 1.1598 / 1.3303 ≈ 0.8718
      expect(rates['GBP'], closeTo(0.8718, 0.0001));
      // HKD normalized = 1.1598 / 0.1276 ≈ 9.0893
      expect(rates['HKD'], closeTo(9.0893, 0.001));
    });

    test('parseBermudaCustomsHtml ignores rows without valid ISO code', () {
      final html = _sampleHtml.replaceAll('(USD)', '()');
      final rates = BermudaCustomsProvider.parseBermudaCustomsHtml(html);
      expect(rates, isNotNull);
      expect(rates!.containsKey('USD'), isFalse);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
    });

    test('parseBermudaCustomsHtml returns null for missing table', () {
      expect(
        BermudaCustomsProvider.parseBermudaCustomsHtml(
          '<html><body></body></html>',
        ),
        isNull,
      );
    });

    test('parseBermudaCustomsHtml returns null for missing EUR', () {
      final html = _sampleHtml.replaceAll('(EUR)', '(XYZ)');
      expect(
        BermudaCustomsProvider.parseBermudaCustomsHtml(html),
        isNull,
      );
    });

    test('fetchRates returns EUR-based rates or null', () async {
      final rates = await BermudaCustomsProvider().fetchRates();
      if (rates == null) {
        print('Bermuda Customs live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BMD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
