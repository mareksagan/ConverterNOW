import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbvsProvider', () {
    test('id and name are correct', () {
      final provider = CbvsProvider();
      expect(provider.id, 'cbvs');
      expect(provider.name, 'Centrale Bank van Suriname');
      expect(provider.initials, 'CBVS');
    });

    test('parseCbvsPdfText extracts rates from PDF text', () {
      // This is the text extracted from the CBVS PDF dated April 29, 2026.
      const sampleText = '''
April 29, 2026determined around 10:00h and valid until further notice CURRENCYBUYING*SELLING*BUYING*SELLING*U.S. DOLLAR (USD)37.222                      37.700          37.496           37.591               EURO (EUR)43.439                      44.100          43.061           43.824             POUND STERLING (GBP)50.135                      51.118          50.505           51.505             CARIBBEAN GUILDER (XCG)20.451                      20.852          20.602           21.010             ARUBAN FLORIN (AWG)20.679                      21.084          20.831           21.244             BRAZILIAN REAL (BRL)7.442                        7.588            7.497             7.645               TRINIDAD & TOBAGO DOLLAR (TTD)5.488                        5.595            5.528             5.638               BARBADOS DOLLAR (BBD)18.349                      18.708          18.484           18.850             EASTERN CARIBBEAN DOLLAR (XCD)13.786                      14.056          13.888           14.163             GUYANA DOLLAR (GYD PER 100 )17.687                      18.033          17.817           18.170             CHINESE YUAN RENMINBI (CNY)5.443                        5.549            5.483             5.591               Note: The above rates are weighted average exchange rates of the USD and EUR on the foreign exchange market,          as reported today to the Bank by the exchange houses and banks, and exchange rate quotes derived from          those rates. These rates are strictly meant to be an orientation to the public and are indicative in nature.         The Bank does not accept responsibility for any inaccuracies.Valid until:29/04/2026SRD   -----------5grams55,330.34                 10grams110,660.68               50grams553,303.42               100grams1,106,606.84            500grams5,533,034.22            1000grams11,066,068.45          Goldprice LBMA*:4,564.90USD per troy oz. (31,1035 gr)* As of 11 July 2022, the Bank uses the goldprice quote of the London Bullion Market Association (LBMA)
NO.079/26
'''; // Note: using $ to ensure the regex sees the numbers correctly

      final result = CbvsProvider.parseCbvsPdfText(sampleText);
      expect(result, isNotNull);
      expect(result!['EUR'], equals(1.0));

      // Verify SRD-based rates are present
      expect(result.containsKey('USD'), isTrue);
      expect(result.containsKey('EUR'), isTrue);
      expect(result.containsKey('GBP'), isTrue);
      expect(result.containsKey('CNY'), isTrue);
      expect(result.containsKey('SRD'), isTrue);
      expect(result.containsKey('XCG'), isTrue);
      expect(result.containsKey('AWG'), isTrue);
      expect(result.containsKey('BRL'), isTrue);
      expect(result.containsKey('TTD'), isTrue);
      expect(result.containsKey('BBD'), isTrue);
      expect(result.containsKey('XCD'), isTrue);
      expect(result.containsKey('GYD'), isTrue);

      // USD mid = (37.222 + 37.700) / 2 = 37.461 SRD per USD
      // EUR mid = (43.439 + 44.100) / 2 = 43.7695 SRD per EUR
      // Normalized USD = EUR rate / USD rate = 43.7695 / 37.461
      expect(result['USD']!, closeTo(43.7695 / 37.461, 0.001));

      // GYD mid = (17.687 + 18.033) / 2 / 100 = 0.1786 SRD per GYD
      // Normalized GYD = 43.7695 / 0.1786
      expect(result['GYD']!, closeTo(43.7695 / 0.1786, 0.01));
    });

    test('fetchRates works with live API', () async {
      final provider = CbvsProvider();
      final rates = await provider.fetchRates();
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('SRD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
