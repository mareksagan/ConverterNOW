import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

void main() {
  group('BCN parseBcnPdf', () {
    const sampleText =
        'BANCO CENTRAL DE NICARAGUA\n'
        'AVISO\n'
        'El Banco Central de Nicaragua informa al público en general los tipos de cambio oficial del\n'
        'córdoba con respecto al dólar de los Estados Unidos de América (USD) que regirán en el\n'
        'período abajo señalado:\n'
        'TIPO DE CAMBIO OFICIAL DE 2026-04-28/2026-04-28\n'
        'Fecha Córdoba por USD\n'
        '28-Abril-2026 36.6243\n'
        'Página 1';

    test('parses USD/NIO rate from PDF text', () {
      final rate = BcnProvider.parseBcnPdf(sampleText);
      expect(rate, isNotNull);
      expect(rate, 36.6243);
    });

    test('returns null for empty text', () {
      expect(BcnProvider.parseBcnPdf(''), isNull);
    });

    test('returns null for text without rate', () {
      expect(BcnProvider.parseBcnPdf('some random text without date or rate'), isNull);
    });
  });

  group('BCN fetchRates live', () {
    test('fetches and parses real rates from BCN (with ECB fallback)', () async {
      final provider = BcnProvider();
      final rates = await provider.fetchRates();
      // BCN employs bot protection (Radware) which may block automated
      // requests. If blocked, the provider should return null gracefully.
      if (rates == null) {
        print('BCN live fetch returned null (likely bot protection)');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('NIO'), isTrue);
      // Normalized to EUR base: EUR = 1.0
      expect(rates['EUR'], closeTo(1.0, 0.001));
      // USD should be around 1.17 (EUR/USD from ECB)
      expect(rates['USD']! > 1.0 && rates['USD']! < 2.0, isTrue);
      // NIO should be around 42-43 (EUR/NIO = EUR/USD × USD/NIO)
      expect(rates['NIO']! > 30 && rates['NIO']! < 60, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
