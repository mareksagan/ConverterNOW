import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BslProvider', () {
    test('id and name are correct', () {
      final provider = BslProvider();
      expect(provider.id, 'bsl');
      expect(provider.name, 'Bank of Sierra Leone');
      expect(provider.initials, 'BSL');
    });

    test('parseBslPdfText extracts rates from PDF text', () {
      const sampleText = '''
BANK OF SIERRA LEONE REFERENCE RATES BANK OF SIERRA LEONE REFERENCE RATES AS AT:
29-Apr-26
CURRENCY EXCHANGE RATE
POUND STERLING 30.7687
POUND STERLING 30.7687 U.S. DOLLAR 22.7925
CANADIAN DOLLAR 16.6574
U.S. DOLLAR 22.7925 SWISS FRANC 28.8786
SWEDISH KRONER 2.4577
SWISS FRANC 28.8786 JAPANESE YEN 0.1426
NORWEGIAN KRONE 2.4481
EURO 26.6592 DANISH KRONE 3.5668
AUSTRALIAN DOLLAR 16.3104
W A U A 31.1883 EURO 26.6592
SAUDI RIYAL 6.0768
KUWAIT DINAH 79.6086
U.A.E.DIRHAMS 6.2054
SOUTH AFRICAN RAND 1.3736
CHINESE RENMINBI 3.3352
HONG KONG 2.9083
S.D.R. 31.2098
CFA FRANC 0.0406
GAMBIAN DALASI 0.3177
GUINEAN FRANC 0.0641
GHANABANK CEDI 2.0545
NAIRA 0.0168
MARKET SURVEILLANCE CENTRAL BANK LIBERIA 0.1238
FINANCIAL MARKETS DEPARTMENT RIMBANK OUGUIYA
CABO VERDE ESCUDOS 0.2416
BUYING SELLING
VALUE TO THE VALUE TO THE
U.S. DOLLAR U.S. DOLLAR B A N K O F S I E R R A L E O N E
POUND STERLING 0.7407 0.7409
CANADIAN DOLLAR 1.3678 1.3688
NOTE: Mid-Rate is Weighted Average Mid-Rate
29-Apr-26
''';

      final result = BslProvider.parseBslPdfText(sampleText);
      expect(result, isNotNull);
      expect(result!['EUR'], equals(1.0));

      // Verify key SLE-based rates are present
      expect(result.containsKey('USD'), isTrue);
      expect(result.containsKey('GBP'), isTrue);
      expect(result.containsKey('EUR'), isTrue);
      expect(result.containsKey('SLE'), isTrue);
      expect(result.containsKey('JPY'), isTrue);
      expect(result.containsKey('XOF'), isTrue);
      expect(result.containsKey('GHS'), isTrue);
      expect(result.containsKey('NGN'), isTrue);
      expect(result.containsKey('LRD'), isTrue);
      expect(result.containsKey('CVE'), isTrue);
      expect(result.containsKey('CNY'), isTrue);

      // SLE rate = EUR rate / 1.0 = 26.6592
      expect(result['SLE']!, closeTo(26.6592, 0.0001));

      // USD normalized = EUR / USD = 26.6592 / 22.7925
      expect(result['USD']!, closeTo(26.6592 / 22.7925, 0.0001));

      // GBP normalized = EUR / GBP = 26.6592 / 30.7687
      expect(result['GBP']!, closeTo(26.6592 / 30.7687, 0.0001));

      // XOF normalized = EUR / XOF = 26.6592 / 0.0406
      // Should be close to the CFA franc's EUR peg (~655.957)
      expect(result['XOF']!, closeTo(26.6592 / 0.0406, 0.1));
    });

    test('fetchRates works with live API', () async {
      final provider = BslProvider();
      final rates = await provider.fetchRates();
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('SLE'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
