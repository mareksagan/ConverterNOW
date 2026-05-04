import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BSP', () {
    const sampleHtml = r'''
<!DOCTYPE html>
<html>
<head><title>Exchange Rates - PNG</title></head>
<body>
<section rel=CBCurrenciesTable>
  <article>
    <table>
      <tbody>
        <tr><td><b>Australian Dollar</b></td><td><b>AUD</b></td><td>0.3244</td></tr>
        <tr><td><b>US Dollar</b></td><td><b>USD</b></td><td>0.2379</td></tr>
        <tr><td><b>Euro</b></td><td><b>EUR</b></td><td>0.1978</td></tr>
      </tbody>
    </table>
  </article>
</section>
<script>
    CBSimpleExchangeRateCalculator(
        null, null, null, null, null, null, null, null, null, null,
        {"AUD":{"code":"AUD","buy_tt":"0.3244","buy_air":"0","buy_notes":"0.3462","sell_notes":"0.2882","sell_tt":"0.3094","decimals":2,"name":"Australian Dollar"},
         "USD":{"code":"USD","buy_tt":"0.2379","buy_air":"0","buy_notes":"0.2442","sell_notes":"0.1935","sell_tt":"0.2229","decimals":2,"name":"US Dollar"},
         "EUR":{"code":"EUR","buy_tt":"0.1978","buy_air":"0","buy_notes":"0.2385","sell_notes":"0.1953","sell_tt":"0.1828","decimals":2,"name":"Euro"}},
        {"code":"PGK","name":"Kina","fee":"K0.00"},
        {"buy_tt":"Bank TT Buy"}
    );
</script>
</body>
</html>
''';

    test('parseBspHtml extracts and inverts rates from embedded JSON', () {
      final rates = BspProvider.parseBspHtml(sampleHtml);
      expect(rates, isNotNull);

      // Rates are inverted: 1 / foreign-per-PGK
      expect(rates!['AUD'], closeTo(1.0 / 0.3244, 0.0001)); // ~3.0826
      expect(rates['USD'], closeTo(1.0 / 0.2379, 0.0001)); // ~4.2034
      expect(rates['EUR'], closeTo(1.0 / 0.1978, 0.0001)); // ~5.0556
    });

    test('parseBspHtml returns null when JSON is missing', () {
      final rates = BspProvider.parseBspHtml('<html><body>no data</body></html>');
      expect(rates, isNull);
    });

    test('parseBspHtml ignores entries with zero or missing buy_tt', () {
      const htmlWithZero = r'''
<script>
CBSimpleExchangeRateCalculator(null, null, null, null, null, null, null, null, null, null,
  {"XXX":{"code":"XXX","buy_tt":"0","decimals":2,"name":"Invalid"},
   "USD":{"code":"USD","buy_tt":"0.2379","decimals":2,"name":"US Dollar"}},
  {"code":"PGK"}, {});
</script>
''';
      final rates = BspProvider.parseBspHtml(htmlWithZero);
      expect(rates, isNotNull);
      expect(rates!.containsKey('XXX'), isFalse);
      expect(rates.containsKey('USD'), isTrue);
    });

    test('Provider live test fetchRates returns rates with EUR present', () async {
      final rates = await BspProvider().fetchRates();
      if (rates != null) {
        expect(rates['EUR'], isNotNull);
        print('BSP live rates count: ${rates.length}');
      } else {
        print('BSP live test returned null (expected in some environments)');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
