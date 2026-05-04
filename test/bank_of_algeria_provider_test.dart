import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = r'''
<div id="organizTable"><table class=""> <thead> <tr style="text-align: center;color: white;background-color: #063765;"><th></th><th>04-05-2026</th></tr></head><tbody style="text-align: center"><tr><td>USD</td><td>132.3182</td><tr><td>EUR</td><td>155.0108</td><tr><td>GBP</td><td>179.4876</td><tr><td>JPY</td><td>84.3221</td><tr><td>CNY</td><td>19.3724</td><tr><td>CHF</td><td>168.9888</td><tr><td>CAD</td><td>97.2428</td><tr><td>DKK</td><td>20.7433</td><tr><td>SEK</td><td>14.3065</td><tr><td>NOK</td><td>14.2707</td><tr><td>AED</td><td>36.0261</td><tr><td>SAR</td><td>35.2802</td><tr><td>KWD</td><td>431.9184</td><tr><td>TND</td><td>45.4265</td><tr><td>MAD</td><td>14.3082</td><tr><td>LYD</td><td>20.8090</td><tr><td>MRU</td><td>3.3238</td><tr><td>SDR</td><td>181.7885</td></tr></tbody></table><table class=""> <thead> <tr style="text-align: center;color: white;background-color: #063765;"><th>30-04-2026</th></tr></head><tbody style="text-align: center"><tr><td>132.5429</td><tr><td>154.7637</td></tr></tbody></table></div>
''';

void main() {
  group('BankOfAlgeriaProvider', () {
    test('id, name and initials are correct', () {
      final p = BankOfAlgeriaProvider();
      expect(p.id, 'bank_of_algeria');
      expect(p.name, 'Bank of Algeria');
      expect(p.initials, 'BoA');
    });

    test('parseBankOfAlgeriaHtml returns EUR-based rates', () {
      final rates = BankOfAlgeriaProvider.parseBankOfAlgeriaHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(1.0, 0.0001));
      // 155.0108 / 132.3182 ≈ 1.1715
      expect(rates['USD'], closeTo(1.1715, 0.0001));
      // DZD rate = 155.0108 / 1.0 = 155.0108
      expect(rates['DZD'], closeTo(155.0108, 0.0001));
      expect(rates['GBP'], closeTo(0.8636, 0.0001));
      expect(rates['JPY'], closeTo(1.8383, 0.0001));
    });

    test('parseBankOfAlgeriaHtml maps SDR to XDR', () {
      final rates = BankOfAlgeriaProvider.parseBankOfAlgeriaHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!.containsKey('SDR'), isFalse);
      expect(rates.containsKey('XDR'), isTrue);
      // 155.0108 / 181.7885 ≈ 0.8527
      expect(rates['XDR'], closeTo(0.8527, 0.0001));
    });

    test('parseBankOfAlgeriaHtml returns null for missing EUR', () {
      final html = _sampleHtml.replaceAll('EUR', 'XXX');
      expect(BankOfAlgeriaProvider.parseBankOfAlgeriaHtml(html), isNull);
    });

    test('parseBankOfAlgeriaHtml returns null for empty table', () {
      expect(
        BankOfAlgeriaProvider.parseBankOfAlgeriaHtml('<html></html>'),
        isNull,
      );
    });

    test('fetchRates returns EUR-based rates or null', () async {
      final rates = await BankOfAlgeriaProvider().fetchRates();
      if (rates == null) {
        print('Bank of Algeria live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('DZD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
