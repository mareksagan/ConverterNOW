import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleXml = r'''
<?xml version="1.0" encoding="UTF-8"?>
<KKTCMB_Doviz_Kurlari>
  <Kur_Tarihi>04/05/2026</Kur_Tarihi>
  <Resmi_Kurlar>
    <Resmi_Kur>
      <Birim>1</Birim>
      <Sembol>USD</Sembol>
      <Doviz_Alis>44.96920</Doviz_Alis>
      <Doviz_Satis>45.05020</Doviz_Satis>
    </Resmi_Kur>
    <Resmi_Kur>
      <Birim>1</Birim>
      <Sembol>EUR</Sembol>
      <Doviz_Alis>52.57230</Doviz_Alis>
      <Doviz_Satis>52.66700</Doviz_Satis>
    </Resmi_Kur>
    <Resmi_Kur>
      <Birim>1</Birim>
      <Sembol>GBP</Sembol>
      <Doviz_Alis>60.60130</Doviz_Alis>
      <Doviz_Satis>60.91730</Doviz_Satis>
    </Resmi_Kur>
    <Resmi_Kur>
      <Birim>100</Birim>
      <Sembol>JPY</Sembol>
      <Doviz_Alis>28.23720</Doviz_Alis>
      <Doviz_Satis>28.42420</Doviz_Satis>
    </Resmi_Kur>
  </Resmi_Kurlar>
</KKTCMB_Doviz_Kurlari>
''';

void main() {
  group('KktcmbProvider', () {
    test('id, name and initials are correct', () {
      final provider = KktcmbProvider();
      expect(provider.id, 'kktcmb');
      expect(provider.name, 'Central Bank of the Turkish Republic of Northern Cyprus');
      expect(provider.initials, 'KKTCMB');
    });

    test('parseKktcmbXml returns normalized rates', () {
      final rates = KktcmbProvider.parseKktcmbXml(_sampleXml);

      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates.containsKey('JPY'), isTrue);
      expect(rates.containsKey('TRY'), isTrue);

      // EUR=52.5723, USD=44.9692 => normalized USD = 52.5723 / 44.9692
      expect(rates['USD'], closeTo(52.5723 / 44.9692, 0.0001));
      // EUR=52.5723, JPY=0.282372 => normalized JPY = 52.5723 / 0.282372
      expect(rates['JPY'], closeTo(52.5723 / 0.282372, 0.0001));
    });

    test('parseKktcmbXml handles missing EUR', () {
      const xml = '<KKTCMB_Doviz_Kurlari><Resmi_Kurlar>'
          '<Resmi_Kur><Birim>1</Birim><Sembol>USD</Sembol>'
          '<Doviz_Alis>44.96920</Doviz_Alis></Resmi_Kur>'
          '</Resmi_Kurlar></KKTCMB_Doviz_Kurlari>';
      expect(KktcmbProvider.parseKktcmbXml(xml), isNull);
    });

    test('parseKktcmbXml returns null for empty XML', () {
      expect(KktcmbProvider.parseKktcmbXml('<root></root>'), isNull);
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = KktcmbProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('KKTCMB live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('TRY'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
