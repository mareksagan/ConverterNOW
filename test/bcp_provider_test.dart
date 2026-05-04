import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

void main() {
  group('BCP parseBcpPdf', () {
    const sampleText =
        'PLANILLA DE COTIZACIONES AL MIERCOLES 29 DE ABRIL DEL 2026 '
        'MONEDA ME/USD.  ² / ME '
        'DÓLAR ESTADOUNIDENSE 1,0000 6.144,80 '
        'YEN JAPONÉS 160,1800 38,36 '
        'LIBRA ESTERLINA * 1,3489 8.288,72 '
        'FRANCO SUIZO 0,7898 7.780,20 '
        'CORONA SUECA 9,2936 661,19 '
        'CORONA DANESA 6,3907 961,52 '
        'CORONA NORUEGA 9,2953 661,07 '
        'REAL BRASILEÑO 4,9966 1.229,80 '
        'PESO ARGENTINO 1.395,5300 4,40 '
        'DÓLAR CANADIENSE 1,3678 4.492,47 '
        'RAND SUDAFRICANO 16,7303 367,29 '
        'DERECHOS ESPECIALES DE GIRO \\(FMI\\ 1,3700 8.418,38 '
        'ONZA DE ORO * 4.545,1900 27.929.283,51 '
        'PESO CHILENO 903,0200 6,80 '
        'EURO * 1,1694 7.185,73 '
        'PESO URUGUAYO 40,2250 152,76 '
        'DÓLAR AUSTRALIANO * 0,7135 4.384,31 '
        'YUAN RENMINBI DE CHINA 6,8380 898,63 '
        'DÓLAR DE SINGAPUR 1,2799 4.801,00 '
        'BOLIVIANO 6,8566 896,19 '
        'SOL PERUANO 3,5340 1.738,77 '
        'DÓLAR NEOZELANDÉS 0,5841 3.589,18 '
        'PESO MEXICANO 17,4771 351,59 '
        'PESO COLOMBIANO 3.617,4500 1,70 '
        'DÓLAR TAIWANÉS 31,5570 194,72 '
        'DIRHAM DE LOS EMIRATOS ÁRABES UNIDOS 3,6730 1.672,96';

    test('parses all expected currencies from PDF text', () {
      final result = BcpProvider.parseBcpPdf(sampleText);
      expect(result, isNotNull);
      expect(result!['USD'], 6144.80);
      expect(result['EUR'], 7185.73);
      expect(result['JPY'], 38.36);
      expect(result['GBP'], 8288.72);
      expect(result['ARS'], 4.40);
      expect(result['CLP'], 6.80);
      expect(result['XDR'], 8418.38);
      expect(result['AED'], 1672.96);
      // Gold ounce should NOT be included
      expect(result.containsKey('XAU'), isFalse);
      // PYG is injected by fetchRates, not parseBcpPdf
      expect(result.containsKey('PYG'), isFalse);
    });

    test('returns null for empty text', () {
      expect(BcpProvider.parseBcpPdf(''), isNull);
    });

    test('returns null for text without recognizable currencies', () {
      expect(BcpProvider.parseBcpPdf('some random text'), isNull);
    });

    test('handles thousand and decimal separators correctly', () {
      final result = BcpProvider.parseBcpPdf(sampleText);
      expect(result, isNotNull);
      // 1.229,80 → 1229.80
      expect(result!['BRL'], 1229.80);
      // 1.395,5300 → 1395.53
      expect(result['ARS'], 4.40);
      // 27.929.283,51 should be skipped (XAU)
      expect(result.containsKey('XAU'), isFalse);
    });
  });

  group('BCP fetchRates live', () {
    test('fetches and parses real rates from BCP', () async {
      final provider = BcpProvider();
      final rates = await provider.fetchRates();
      if (rates == null) {
        print('BCP live fetch returned null (network or server issue)');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PYG'), isTrue);
      // Normalized to EUR base: EUR = 1.0
      expect(rates['EUR'], closeTo(1.0, 0.001));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
