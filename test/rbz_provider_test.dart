import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RbzProvider', () {
    test('id and name are correct', () {
      final provider = RbzProvider();
      expect(provider.id, 'rbz');
      expect(provider.name, 'Reserve Bank of Zimbabwe');
      expect(provider.initials, 'RBZ');
    });

    test('parses April 29 2026 PDF text correctly', () {
      final provider = RbzProvider();
      // ignore: invalid_use_of_visible_for_testing_member
      final rates = provider.parseRbzPdf(_april29PdfText);

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ZWG'), isTrue);

      // Normalised rates are EUR-based.  Sanity-check a few key
      // currencies against the values computed from the PDF
      // (tolerance ±3 % to allow for minor rounding differences).
      expect(rates['USD'], closeTo(0.854, 0.03));
      expect(rates['GBP'], closeTo(1.154, 0.04));
      expect(rates['ZAR'], closeTo(0.0516, 0.002));
      expect(rates['JPY'], closeTo(0.00535, 0.0002));
      expect(rates['ZMW'], closeTo(0.0446, 0.002));
      expect(rates['CAD'], closeTo(0.624, 0.02));
      expect(rates['INR'], closeTo(0.0090, 0.0003));
      expect(rates['XAF'], closeTo(0.00149, 0.00005));
    });

    test('fetchRates works with live API', () async {
      final provider = RbzProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('ZWG'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['ZWG'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

const _april29PdfText = '''
CURRENCY INDICES BID ASK MID RATE BID RATE ASK RATE MID RATE
ZWG ZWG ZWG
INTERBANK RATE
USD 1 1 1.0000 24.6652 25.9300 25.2976
ZAR 16.5487 16.5618 16.55525 0.6382 0.6714 0.6548
GBP * 1.3507 1.3510 1.35085 33.3152 35.0314 34.1733
JPY 159.6400 159.6800 159.66000 6.1565 6.4738 6.3152
ZMW/ZMK 18.9170 19.3310 19.12400 0.7295 0.7837 0.7566
BWP 0.0705 0.0718 0.07115 1.7388 1.8617 1.8003
CHF 0.7892 0.7895 0.78935 31.2415 32.8560 32.0488
MWK 1717.0200 1750.3200 1,733.67000 66.2175 70.9631 68.5903
AUD * 0.7163 0.7164 0.71635 17.6676 18.5762 18.1219
SDR * 1.369340 1.369340 1.36934 34.6410 34.6410 34.6410
MZN/MET 63.2400 63.9400 63.59000 2.4388 2.5923 2.5156
NOK 9.3206 9.3360 9.32830 0.3594 0.3785 0.3690
SEK 9.2776 9.2808 9.27920 0.3577 0.3762 0.3670
CAD * 1.3688 1.3689 1.36885 0.0527 0.0554 0.0541
EUR * 1.1702 1.1704 1.17030 28.8632 30.3484 29.6058
CNY 6.8362 6.8363 6.83625 0.2636 0.2771 0.2704
INR 94.7650 94.7750 94.77000 3.6546 3.8424 3.7485
NZD * 0.5860 0.5862 0.58610 14.4538 15.2001 14.8270
DKK 6.3861 6.3865 6.38630 0.2462 0.2589 0.2526
XAU 4598.5400 4599.1900 4,598.86500 113423.9088 119256.9967 116340.4528
AFN 64.2600 64.4600 64.36000 2.4782 2.6133 2.5458
THB 32.5800 32.6100 32.59500 1.2564 1.3221 1.2893
ETB 157.3647 158.3647 157.86470 6.0688 6.4205 6.2447
SZL 16.5378 16.5698 16.55380 0.6377 0.6717 0.6547
MUR 46.6800 46.9800 46.83000 1.8002 1.9047 1.8525
MYR 3.9480 3.9530 3.95050 0.1522 0.1602 0.1562
LSL 16.5538 16.5567 16.55525 0.6384 0.6712 0.6548
CYP * 0.3975 0.3980 0.39775 0.0153 0.0161 0.0157
EGP 52.7800 52.8800 52.83000 2.0354 2.1439 2.0897
BRL 4.9760 4.9769 4.97645 0.1919 0.2017 0.1968
TZS 2595.0000 2635.0000 2,615.00000 100.0771 106.8306 103.4539
RUB 75.1500 75.1700 75.16000 2.8981 3.0476 2.9729
KES 129.1000 129.3000 129.20000 4.9787 5.2422 5.1105
DEM 2.2150 2.2175 2.21625 0.0854 0.0899 0.0877
ESP 188.4300 188.6500 188.54000 7.2668 7.6484 7.4576
ITL 2192.8300 2195.3200 2,194.07500 84.5672 89.0047 86.7860
FRF 7.4287 7.4372 7.43295 0.2864 0.3015 0.2940
HKD 7.7495 7.8374 7.79345 0.2988 0.3177 0.3083
ARS 1404.5000 1405.0000 1,404.75000 54.1650 56.9628 55.5639
XAF 560.4600 585.5600 573.01000 21.6143 23.7403 22.6773
Wednesday, April 29, 2026
''';
