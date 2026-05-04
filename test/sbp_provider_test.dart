import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SbpProvider', () {
    test('id and name are correct', () {
      final provider = SbpProvider();
      expect(provider.id, 'sbp');
      expect(provider.name, 'State Bank of Pakistan');
      expect(provider.initials, 'SBP');
    });

    test('parseSbpPdfText extracts rates from PDF text', () {
      const sampleText = '''
CURRENCY BUYING SELLING
AED 75.8638 75.9737
AUD 198.2289 198.5365
CAD 203.5291 203.8411
CHF 351.7937 352.3352
CNY 40.7495 40.8020
EUR 324.8434 325.3368
GBP 375.0420 375.6155
JPY 1.7344 1.7370
SAR 74.2535 74.3617
USD 278.5150 278.9401
STATE BANK OF PAKISTAN
'''; // ignore: invalid_use_of_visible_for_testing_member
      final result = SbpProvider.parseSbpPdfText(sampleText);

      expect(result, isNotNull);
      expect(result!['EUR'], equals(1.0));

      // Verify PKR-based rates are present
      expect(result.containsKey('USD'), isTrue);
      expect(result.containsKey('EUR'), isTrue);
      expect(result.containsKey('GBP'), isTrue);
      expect(result.containsKey('JPY'), isTrue);
      expect(result.containsKey('PKR'), isTrue);
      expect(result.containsKey('AED'), isTrue);
      expect(result.containsKey('SAR'), isTrue);
      expect(result.containsKey('CNY'), isTrue);
      expect(result.containsKey('AUD'), isTrue);
      expect(result.containsKey('CAD'), isTrue);
      expect(result.containsKey('CHF'), isTrue);

      // USD mid = (278.5150 + 278.9401) / 2 = 278.72755 PKR per USD
      // EUR mid = (324.8434 + 325.3368) / 2 = 325.0901 PKR per EUR
      // Normalized USD = EUR rate / USD rate = 325.0901 / 278.72755
      expect(result['USD']!, closeTo(325.0901 / 278.72755, 0.0001));

      // JPY mid = (1.7344 + 1.7370) / 2 = 1.7357 PKR per JPY
      // Normalized JPY = 325.0901 / 1.7357
      expect(result['JPY']!, closeTo(325.0901 / 1.7357, 0.001));
    });

    test('fetchRates works with live API', () async {
      final provider = SbpProvider();
      final rates = await provider.fetchRates();
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PKR'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
