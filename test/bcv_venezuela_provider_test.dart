import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BcvVenezuelaProvider', () {
    test('id and name are correct', () {
      final provider = BcvVenezuelaProvider();
      expect(provider.id, 'bcv_venezuela');
      expect(provider.name, 'Banco Central de Venezuela');
      expect(provider.initials, 'BCV');
    });

    test('parseBcvVenezuelaHtml extracts rates from HTML', () {
      const sampleHtml = '''
<div id="euro" class="col-sm-12 col-xs-12 ">
  <div class="field-content">
    <div class="row recuadrotsmc">
      <div class="col-sm-6 col-xs-6">
        <img src="/sites/default/files/euro-04_2.png" class="icono_bss_blanco1">
        <span> EUR </span>
      </div>
      <div class="col-sm-6 col-xs-6 centrado"><strong> 574,19381208 </strong> </div>
    </div>
  </div>
</div>
<div id="dolar" class="col-sm-12 col-xs-12 ">
  <div class="field-content">
    <div class="row recuadrotsmc">
      <div class="col-sm-6 col-xs-6">
        <img src="/sites/default/files/dollar-04_2.png" class="icono_bss_blanco1">
        <span> USD</span>
      </div>
      <div class="col-sm-6 col-xs-6 centrado"><strong> 489,55470000 </strong> </div>
    </div>
  </div>
</div>
<div id="yuan" class="col-sm-12 col-xs-12">
  <div class="field-content">
    <div class="row recuadrotsmc">
      <div class="col-sm-6 col-xs-6">
        <img src="/sites/default/files/yuan-04_2.png" class="icono_bss_blanco1">
        <span> CNY </span>
      </div>
      <div class="col-sm-6 col-xs-6 centrado"><strong> 71,70546189 </strong> </div>
    </div>
  </div>
</div>
<div id="lira" class="col-sm-12 col-xs-12">
  <div class="field-content">
    <div class="row recuadrotsmc">
      <div class="col-sm-6 col-xs-6">
        <img src="/sites/default/files/default_images/lirat-04_0.png" class="icono_bss_blanco1">
        <span> TRY</span>
      </div>
      <div class="col-sm-6 col-xs-6 centrado"><strong> 10,83507516 </strong> </div>
    </div>
  </div>
</div>
<div id="rublo" class="col-sm-12 col-xs-12 ">
  <div class="field-content">
    <div class="row recuadrotsmc">
      <div class="col-sm-6 col-xs-6">
        <img src="/sites/default/files/rublo-04_2.png" class="icono_bss_blanco1">
        <span> RUB</span>
      </div>
      <div class="col-sm-6 col-xs-6 centrado"><strong> 6,53440959 </strong> </div>
    </div>
  </div>
</div>
''';

      final result = BcvVenezuelaProvider.parseBcvVenezuelaHtml(sampleHtml);
      expect(result, isNotNull);
      expect(result!['EUR'], equals(1.0));

      // Verify currencies are present
      expect(result.containsKey('USD'), isTrue);
      expect(result.containsKey('CNY'), isTrue);
      expect(result.containsKey('TRY'), isTrue);
      expect(result.containsKey('RUB'), isTrue);
      expect(result.containsKey('VES'), isTrue);

      // USD mid = 489.5547 VES per USD
      // EUR mid = 574.19381208 VES per EUR
      // Normalized USD = EUR rate / USD rate = 574.19381208 / 489.5547
      expect(result['USD']!, closeTo(574.19381208 / 489.5547, 0.001));

      // Normalized CNY = 574.19381208 / 71.70546189
      expect(result['CNY']!, closeTo(574.19381208 / 71.70546189, 0.001));
    });

    test('fetchRates works with live API', () async {
      final provider = BcvVenezuelaProvider();
      final rates = await provider.fetchRates();
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('VES'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
