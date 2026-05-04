import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SamaProvider', () {
    test('id and name are correct', () {
      final provider = SamaProvider();
      expect(provider.id, 'sama');
      expect(provider.name, 'Saudi Arabian Monetary Authority');
      expect(provider.initials, 'SAMA');
    });

    test('parses sample JSON correctly', () {
      final provider = SamaProvider();
      // ignore: invalid_use_of_visible_for_testing_member
      final rates = provider.parseSamaJson(_sampleJson);

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('SAR'), isTrue);
      expect(rates.containsKey('USD'), isTrue);

      // SAMA rates are SAR per foreign unit.
      // Normalised to EUR base:
      //   EUR rate = 4.3875 SAR/EUR
      //   USD rate = 3.75 SAR/USD
      //   normalised USD = 4.3875 / 3.75 ≈ 1.17
      expect(rates['USD'], closeTo(1.17, 0.01));

      // JPY rate = 0.02342 SAR/JPY
      // normalised JPY = 4.3875 / 0.02342 ≈ 187.3
      expect(rates['JPY'], closeTo(187, 2));

      // Defunct currencies should be skipped
      expect(rates.containsKey('CYP'), isFalse);
      expect(rates.containsKey('MTL'), isFalse);
      expect(rates.containsKey('SKK'), isFalse);
      expect(rates.containsKey('SDR'), isFalse);
    });

    test('fetchRates works with live API', () async {
      final provider = SamaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('SAR'), isTrue);
      expect(rates.containsKey('USD'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['SAR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

const _sampleJson = '''
{"itemsCount":73,"data":[
{"CurrencyCode":"SAR=","Title":"SAUDI RIYAL","CurrencyRate":1.00000000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"USD=","Title":"US DOLLAR","CurrencyRate":3.75000000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"EUR=","Title":"EURO","CurrencyRate":4.38750000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"GBP=","Title":"POUND STERLING","CurrencyRate":5.06306000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CHF=","Title":"SWISS FRANC","CurrencyRate":4.74833000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"JPY=","Title":"JAPANESE YEN","CurrencyRate":0.02342000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CNY=","Title":"YUAN RENMINBI","CurrencyRate":0.54878000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"PKR=","Title":"PAKISTN RUPEE","CurrencyRate":0.01344000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"INR=","Title":"INDIAN RUPEE ","CurrencyRate":0.03953000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"QAR=","Title":"QATRI RIAL","CurrencyRate":1.02993000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"KWD=","Title":"KUWAITI DINAR","CurrencyRate":12.17532000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"OMR=","Title":"RIAL OMAINI","CurrencyRate":9.74025000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BHD=","Title":"BAHRAINI DINAR","CurrencyRate":9.93377000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"JOD=","Title":"JORDANIAN DINA","CurrencyRate":5.28913000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BAM=","Title":"BOSNIA HERZ","CurrencyRate":2.24329000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BDT=","Title":"BANGLADESH TAK","CurrencyRate":0.03046000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BGN=","Title":"LEV BULGARIA","CurrencyRate":2.24329000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BND=","Title":"BRUNEI DOLLAR","CurrencyRate":2.92912000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"BRL=","Title":"BRAZILIAN REAL","CurrencyRate":0.75048000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CAD=","Title":"CANADIAN DOLLA","CurrencyRate":2.74162000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"ALL=","Title":"LEK ALBANIA","CurrencyRate":0.04591000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CUP=","Title":"CUBA PESOS","CurrencyRate":0.15625000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CYP=","Title":"CYPRUS POUND","CurrencyRate":7.49625000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"CZK=","Title":"CZECH KORUNA","CurrencyRate":0.17987000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"DJF=","Title":"DJIBOUTI FRANC","CurrencyRate":0.02110000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"DKK=","Title":"DANISH KRONE","CurrencyRate":0.58713000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"DZD=","Title":"ALGERIAN DINAR","CurrencyRate":0.02828000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"EGP=","Title":"EGYPTION POUND","CurrencyRate":0.07075000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"ETB=","Title":"ETHIOPIAN BIRR","CurrencyRate":0.02382000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"AFN=","Title":"AFGHANI STAN","CurrencyRate":0.05822000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"ARS=","Title":"ARGENTINE PESO","CurrencyRate":0.00268000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"GNF=","Title":"GUINEA FRANC","CurrencyRate":0.00042000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"HKD=","Title":"HONKONG DOLLAR","CurrencyRate":0.47850000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"AED=","Title":"UAE DIRHAM","CurrencyRate":1.02092000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"IDR=","Title":"INDONESIA RUPI","CurrencyRate":0.00021000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"ISK=","Title":"ICELAND KRONA","CurrencyRate":0.03055000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"AUD=","Title":"AUSTRAL.DOLLAR","CurrencyRate":2.67806000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"KES=","Title":"KENYAN SHILLIN","CurrencyRate":0.02903000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"KRW=","Title":"SOUTH KOREN","CurrencyRate":0.00253000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"LBP=","Title":"LEBANAN LIRA","CurrencyRate":0.00004000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"LKR=","Title":"SIRLANKA RUPEE","CurrencyRate":0.01173000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"LYD=","Title":"LIBYAN DINAR","CurrencyRate":0.59100000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MAD=","Title":"MOROCCO DIRHAM","CurrencyRate":0.40544000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MGA=","Title":"MADAGASCAR ARI","CurrencyRate":0.00090000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MMK=","Title":"KYAT MYANMAR","CurrencyRate":0.00178000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MTL=","Title":"MALTESE LIRA","CurrencyRate":10.21312000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MUR=","Title":"MAURITIUS RUPE","CurrencyRate":0.08011000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MXN=","Title":"MEXICAN PESO","CurrencyRate":0.21465000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"MYR=","Title":"MALAYSIA RINGG","CurrencyRate":0.94900000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"NGN=","Title":"NAIRA NIGERIA","CurrencyRate":0.00273000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"NOK=","Title":"NORWEGIAN KRON","CurrencyRate":0.40369000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"NZD=","Title":"N.ZEALAND DOLL","CurrencyRate":2.19225000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"PHP=","Title":"PHILIPPINE PES","CurrencyRate":0.06090000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"PLN=","Title":"ZLOTY POLAND","CurrencyRate":1.03084000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"RON=","Title":"NEW ROMANIAN L","CurrencyRate":0.86025000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"RUB=","Title":"RUSSIAN RUBLE","CurrencyRate":0.04996000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"SDR=","Title":"S.DRAWING RIGH","CurrencyRate":5.13757000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"SEK=","Title":"SWEDISH KRONA","CurrencyRate":0.40374000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"SGD=","Title":"SINGAPORE DOLL","CurrencyRate":2.93060000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"SKK=","Title":"SLOVAK KORUNA","CurrencyRate":0.14563000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"THB=","Title":"BAHT THAILAND","CurrencyRate":0.11455000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"TJS=","Title":"TAJIKI. SOMONI","CurrencyRate":0.39787000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"TND=","Title":"TUNISIAN DINAR","CurrencyRate":1.30057000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"TRY=","Title":"NEW TURKISH LI","CurrencyRate":0.08320000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"TWD=","Title":"TAIWAN DOLLAR","CurrencyRate":0.11877000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"TZS=","Title":"TANZAN SHILLIN","CurrencyRate":0.00143000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"UGX=","Title":"UGANDA SHILLIN","CurrencyRate":0.00100000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"VND=","Title":"DONG VIET NAM","CurrencyRate":0.00014000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"XAF=","Title":"CAMEROON FRANC","CurrencyRate":0.00668000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"XOF=","Title":"NIGER FRANC","CurrencyRate":0.00668000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"YER=","Title":"YEMENI RIAL","CurrencyRate":0.01572000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"ZAR=","Title":"RAND SOUTH AFR","CurrencyRate":0.22431000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"},
{"CurrencyCode":"HUF=","Title":"HUNGARY FORINT","CurrencyRate":0.01201000,"PrevRate":-1.0,"PrevDate":"0001-01-01T00:00:00","IsGCC":false,"CurrencyDate":"2026-04-30T00:00:00"}
]}
''';
