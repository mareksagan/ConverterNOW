import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleXml = r'''
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices">
  <entry>
    <content type="application/xml">
      <m:properties xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata">
        <d:Symbol>USD</d:Symbol>
        <d:EURequivalent>0.851716</d:EURequivalent>
      </m:properties>
    </content>
  </entry>
  <entry>
    <content type="application/xml">
      <m:properties>
        <d:Symbol>JPY</d:Symbol>
        <d:EURequivalent>0.005435</d:EURequivalent>
      </m:properties>
    </content>
  </entry>
  <entry>
    <content type="application/xml">
      <m:properties>
        <d:Symbol>GBP</d:Symbol>
        <d:EURequivalent>1.158845</d:EURequivalent>
      </m:properties>
    </content>
  </entry>
  <entry>
    <content type="application/xml">
      <m:properties>
        <d:Symbol>EUR</d:Symbol>
        <d:EURequivalent>1.000000</d:EURequivalent>
      </m:properties>
    </content>
  </entry>
  <entry>
    <content type="application/xml">
      <m:properties>
        <d:Symbol>KWD</d:Symbol>
        <d:EURequivalent>N/A</d:EURequivalent>
      </m:properties>
    </content>
  </entry>
</feed>
''';

void main() {
  group('BangkoSentralProvider', () {
    test('id, name and initials are correct', () {
      final provider = BangkoSentralProvider();
      expect(provider.id, 'bangko_sentral');
      expect(provider.name, 'Bangko Sentral ng Pilipinas');
      expect(provider.initials, 'BSP');
    });

    test('parseBangkoSentralXml returns EUR-based rates', () {
      final rates = BangkoSentralProvider.parseBangkoSentralXml(_sampleXml);

      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates['USD'], closeTo(0.851716, 0.00001));
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates['GBP'], closeTo(1.158845, 0.00001));
      expect(rates.containsKey('JPY'), isTrue);
      expect(rates['JPY'], closeTo(0.005435, 0.00001));
      expect(rates.containsKey('PHP'), isTrue);
      expect(rates['PHP'], equals(1.0));
      expect(rates.containsKey('KWD'), isFalse);
    });

    test('parseBangkoSentralXml returns null for missing EUR', () {
      const xml = '<feed><entry><content><m:properties>'
          '<d:Symbol>USD</d:Symbol><d:EURequivalent>0.85</d:EURequivalent>'
          '</m:properties></content></entry></feed>';
      expect(BangkoSentralProvider.parseBangkoSentralXml(xml), isNull);
    });

    test('parseBangkoSentralXml returns null for empty feed', () {
      expect(BangkoSentralProvider.parseBangkoSentralXml('<feed></feed>'), isNull);
    });

    test('fetchRates returns EUR-based rates', () async {
      final provider = BangkoSentralProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('Bangko Sentral live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('PHP'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
