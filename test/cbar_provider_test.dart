import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

const _sampleXml = r'''
<?xml version="1.0" encoding="UTF-8"?>
<ValCurs Date="30.04.2026" Name="AZN məzənnələri" Description="...">
<ValType Type="Bank metalları">
<Valute Code="XPD">
<Nominal>1 t.u.</Nominal>
<Name>Palladium</Name>
<Value>2479.977</Value>
</Valute>
<Valute Code="XAU">
<Nominal>1 t.u.</Nominal>
<Name>Qızıl</Name>
<Value>7722.7005</Value>
</Valute>
</ValType>
<ValType Type="Xarici valyutalar">
<Valute Code="USD">
<Nominal>1</Nominal>
<Name>1 US Dollar</Name>
<Value>1.7</Value>
</Valute>
<Valute Code="EUR">
<Nominal>1</Nominal>
<Name>1 Euro</Name>
<Value>1.9824</Value>
</Valute>
<Valute Code="GBP">
<Nominal>1</Nominal>
<Name>1 British Pound Sterling</Name>
<Value>2.2886</Value>
</Valute>
<Valute Code="KRW">
<Nominal>100</Nominal>
<Name>100 South Korean Won</Name>
<Value>0.1144</Value>
</Valute>
<Valute Code="RUB">
<Nominal>100</Nominal>
<Name>100 Russian Ruble</Name>
<Value>2.2701</Value>
</Valute>
</ValType>
</ValCurs>
''';

const _emptyCurrenciesXml = r'''
<?xml version="1.0" encoding="UTF-8"?>
<ValCurs Date="30.04.2026" Name="AZN məzənnələri">
<ValType Type="Xarici valyutalar">
</ValType>
</ValCurs>
''';

const _noCurrenciesXml = r'''
<?xml version="1.0" encoding="UTF-8"?>
<ValCurs Date="30.04.2026" Name="AZN məzənnələri">
<ValType Type="Bank metalları">
<Valute Code="XAU">
<Nominal>1 t.u.</Nominal>
<Value>7722.7005</Value>
</Valute>
</ValType>
</ValCurs>
''';

void main() {
  group('CBAR parseCbarXml', () {
    test('parses all currencies and skips metals', () {
      final rates = CbarProvider.parseCbarXml(_sampleXml);
      expect(rates, isNotNull);
      expect(rates!.length, 5);
      expect(rates['USD'], closeTo(1.7, 0.0001));
      expect(rates['EUR'], closeTo(1.9824, 0.0001));
      expect(rates['GBP'], closeTo(2.2886, 0.0001));
      // Metals should be skipped
      expect(rates.containsKey('XAU'), isFalse);
      expect(rates.containsKey('XPD'), isFalse);
      expect(rates.containsKey('XAG'), isFalse);
      expect(rates.containsKey('XPT'), isFalse);
    });

    test('adjusts for nominal > 1', () {
      final rates = CbarProvider.parseCbarXml(_sampleXml);
      expect(rates, isNotNull);
      // KRW: 0.1144 AZN per 100 KRW → 0.001144 per 1 KRW
      expect(rates!['KRW'], closeTo(0.001144, 0.0000001));
      // RUB: 2.2701 AZN per 100 RUB → 0.022701 per 1 RUB
      expect(rates['RUB'], closeTo(0.022701, 0.0000001));
    });

    test('returns null for empty currencies', () {
      final rates = CbarProvider.parseCbarXml(_emptyCurrenciesXml);
      expect(rates, isNull);
    });

    test('returns null when only metals are present', () {
      final rates = CbarProvider.parseCbarXml(_noCurrenciesXml);
      expect(rates, isNull);
    });

    test('returns null for invalid XML', () {
      final rates = CbarProvider.parseCbarXml('not xml');
      expect(rates, isNull);
    });
  });

  group('CBAR Provider live test', () {
    test('fetchRates returns rates with EUR present', () async {
      final provider = CbarProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('CBAR live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('AZN'), isTrue);
      expect(rates['AZN'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
