import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

void main() {
  group('BCCh parseBcchHtml', () {
    const sampleHtml = r'''
<!DOCTYPE html>
<html>
<body>
<table id="tbl_lista_series">
<tr><td style="text-align: left;">Thai baht  </td><td style="text-align: center;">27.51</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_THB&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Panamanian Balboa</td><td style="text-align: center;">901.76</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_PAB&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Euro</td><td style="text-align: center;">1,052.60</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_EUR&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Bolivian peso</td><td style="text-align: center;">131.45</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_BOL&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Venezuelan bolívar fuerte</td><td style="text-align: center;">1.86</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_VEB&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">SDR</td><td style="text-align: center;">1,235.46</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_DEG&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Bahamian Dollar</td><td style="text-align: center;">901.76</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_BSP&param=abc">View serie</a></td></tr>
<tr><td style="text-align: left;">Russian ruble</td><td style="text-align: center;">10.85</td><td style="text-align: center;"><a href="Serie.aspx?gcode=TCN_RUR&param=abc">View serie</a></td></tr>
</table>
</body>
</html>
''';

    test('parses all expected currencies and maps non-standard codes', () {
      final result = BcchProvider.parseBcchHtml(sampleHtml);
      expect(result, isNotNull);
      expect(result!['THB'], 27.51);
      expect(result['PAB'], 901.76);
      expect(result['EUR'], 1052.60);
      // Non-standard code mappings
      expect(result['BOB'], 131.45); // BOL → BOB
      expect(result['XDR'], 1235.46); // DEG → XDR
      expect(result['BSD'], 901.76); // BSP → BSD
      expect(result['RUB'], 10.85); // RUR → RUB
      // Obsolete VEB should be skipped
      expect(result.containsKey('VEB'), isFalse);
      // CLP is injected by fetchRates, not parseBcchHtml
      expect(result.containsKey('CLP'), isFalse);
    });

    test('returns null for empty HTML', () {
      expect(BcchProvider.parseBcchHtml(''), isNull);
    });

    test('returns null for HTML without table rows', () {
      expect(BcchProvider.parseBcchHtml('<html><body>no data</body></html>'), isNull);
    });
  });

  group('BCCh fetchRates live', () {
    test('fetches and parses real rates from BCCh', () async {
      final provider = BcchProvider();
      final rates = await provider.fetchRates();
      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CLP'), isTrue);
      // Normalized rates: EUR = 1.0, CLP ≈ eurRate, USD ≈ eurRate/usdRate
      expect(rates['EUR'], closeTo(1.0, 0.001));
      expect(rates['CLP']! > 500, isTrue);
      expect(rates['USD']! > 0.5 && rates['USD']! < 2.0, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
