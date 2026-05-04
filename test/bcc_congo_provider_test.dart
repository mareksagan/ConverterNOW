import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = '''
<table class="table">
  <thead>
    <tr> 
      <th>Unité</th>
      <th>Code</th>
      <th>Libellé</th>
      <th>Cours indicatif</th>
    </tr> 
  </thead>
  <tbody>
    <tr class="">
      <th scope="row">1</th>
      <td>AOA</td>
      <td>KWANZA  ANGOLAIS</td>
      <!-- <td>2,4618</td> -->
      <td>2,5120</td>
      <!-- <td>2,5623</td>-->
    </tr>
    <tr class="table-info">
      <th scope="row">1</th>
      <td>EUR</td>
      <td>EURO</td>
      <!-- <td>2 634,2109</td> -->
      <td>2 687,9703</td>
      <!-- <td>2 741,7297</td>-->
    </tr>
    <tr class="">
      <th scope="row">1</th>
      <td>USD</td>
      <td>DOLLAR AMERICAIN</td>
      <!-- <td>2 255,6026</td> -->
      <td>2 301,6353</td>
      <!-- <td>2 347,6680</td>-->
    </tr>
  </tbody>
</table>
''';

void main() {
  group('BccCongoProvider', () {
    test('id, name and initials are correct', () {
      final p = BccCongoProvider();
      expect(p.id, 'bcc_congo');
      expect(p.name, 'Banque Centrale du Congo');
      expect(p.initials, 'BCC');
    });

    test('parseBccCongoHtml computes rates from first table', () {
      final rates = BccCongoProvider.parseBccCongoHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(1.0, 0.0001));
      // EUR = 2687.9703, USD = 2301.6353, CDF = 1.0
      // USD normalized = 2687.9703 / 2301.6353 ≈ 1.1679
      expect(rates['USD'], closeTo(1.1679, 0.0001));
      // CDF normalized = 2687.9703 / 1.0 = 2687.9703
      expect(rates['CDF'], closeTo(2687.9703, 0.001));
      // AOA normalized = 2687.9703 / 2.5120 ≈ 1070.051
      expect(rates['AOA'], closeTo(1070.051, 0.001));
    });

    test('parseBccCongoHtml ignores rows without valid ISO code', () {
      final html = _sampleHtml.replaceAll('<td>USD</td>', '<td>US DOLLAR</td>');
      final rates = BccCongoProvider.parseBccCongoHtml(html);
      expect(rates, isNotNull);
      expect(rates!.containsKey('USD'), isFalse);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
    });

    test('parseBccCongoHtml returns null for missing table', () {
      expect(
        BccCongoProvider.parseBccCongoHtml('<html><body></body></html>'),
        isNull,
      );
    });

    test('parseBccCongoHtml returns null for missing EUR', () {
      final html = _sampleHtml.replaceAll('<td>EUR</td>', '<td>XYZ</td>');
      expect(
        BccCongoProvider.parseBccCongoHtml(html),
        isNull,
      );
    });

    test('fetchRates returns EUR-based rates or null', () async {
      final rates = await BccCongoProvider().fetchRates();
      if (rates == null) {
        print('Banque Centrale du Congo live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CDF'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
