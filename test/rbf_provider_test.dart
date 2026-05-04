import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

// Sample HTML snippet from https://www.rbf.gov.fj/
const _sampleHtml = r'''
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>USD</h4><div class="desc">0.4488</div></div>
</div>
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>EURO</h4><div class="desc">0.3844</div></div>
</div>
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>AUD</h4><div class="desc">0.6304</div></div>
</div>
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>NZD</h4><div class="desc">0.7697</div></div>
</div>
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>JPY</h4><div class="desc">72.00</div></div>
</div>
<div class="list_item lists_2 clearfix">
  <div class="list_left list_image"><img src="flag.png"/></div>
  <div class="list_right"><h4>GBP</h4><div class="desc">0.3330</div></div>
</div>
''';

const _emptyRatesHtml = '<html><body><p>No rates today</p></body></html>';

void main() {
  group('RBF parseRbfHtml', () {
    test('parses all six currencies and inverts rates', () {
      final rates = RbfProvider.parseRbfHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!.length, 6);

      // Rates are inverted: 1 / foreign-per-FJD = FJD-per-foreign
      expect(rates['USD'], closeTo(1 / 0.4488, 0.0001));
      expect(rates['EUR'], closeTo(1 / 0.3844, 0.0001));
      expect(rates['AUD'], closeTo(1 / 0.6304, 0.0001));
      expect(rates['NZD'], closeTo(1 / 0.7697, 0.0001));
      expect(rates['JPY'], closeTo(1 / 72.00, 0.0001));
      expect(rates['GBP'], closeTo(1 / 0.3330, 0.0001));
    });

    test('maps EURO to EUR', () {
      final rates = RbfProvider.parseRbfHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates.containsKey('EURO'), isFalse);
    });

    test('returns null for empty rates', () {
      final rates = RbfProvider.parseRbfHtml(_emptyRatesHtml);
      expect(rates, isNull);
    });

    test('returns null for invalid HTML', () {
      final rates = RbfProvider.parseRbfHtml('not html');
      expect(rates, isNull);
    });
  });

  group('RBF Provider live test', () {
    test('fetchRates returns rates with EUR present', () async {
      final provider = RbfProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('RBF live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('FJD'), isTrue);
      expect(rates['FJD'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
