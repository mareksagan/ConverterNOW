import 'package:flutter_test/flutter_test.dart';
import 'package:converterpro/models/currency_provider.dart';

// Sample JSON response from the CBTT wpDataTables endpoint
const _sampleJson = r'''
{
  "draw": 16,
  "recordsTotal": "12896",
  "recordsFiltered": "1",
  "data": [
    [
      "01/05/2026",
      "2.7086", "3.7098",
      "4.9450", "5.4143",
      "8.5755", "9.2708",
      "2.4209", "2.5651",
      "9.1314", "9.9575",
      "0.0312", "0.0324",
      "0.0413", "0.0430",
      "0.0427", "0.0431",
      "6.7031", "6.7609",
      "7.8965", "9.0179"
    ]
  ]
}
''';

const _emptyDataJson = r'{"draw":1,"recordsTotal":"0","recordsFiltered":"0","data":[]}';
const _missingDataJson = r'{"draw":1,"recordsTotal":"0","recordsFiltered":"0"}';

void main() {
  group('CBTT parseCbttJson', () {
    test('parses all buying rates from sample JSON', () {
      final rates = CbttProvider.parseCbttJson(_sampleJson);
      expect(rates, isNotNull);
      expect(rates!.length, 10);
      expect(rates['BBD'], closeTo(2.7086, 0.0001));
      expect(rates['CAD'], closeTo(4.9450, 0.0001));
      expect(rates['CHF'], closeTo(8.5755, 0.0001));
      expect(rates['XCD'], closeTo(2.4209, 0.0001));
      expect(rates['GBP'], closeTo(9.1314, 0.0001));
      expect(rates['GYD'], closeTo(0.0312, 0.0001));
      expect(rates['JMD'], closeTo(0.0413, 0.0001));
      expect(rates['JPY'], closeTo(0.0427, 0.0001));
      expect(rates['USD'], closeTo(6.7031, 0.0001));
      expect(rates['EUR'], closeTo(7.8965, 0.0001));
    });

    test('returns null for empty data array', () {
      final rates = CbttProvider.parseCbttJson(_emptyDataJson);
      expect(rates, isNull);
    });

    test('returns null when data field is missing', () {
      final rates = CbttProvider.parseCbttJson(_missingDataJson);
      expect(rates, isNull);
    });

    test('returns null for malformed row', () {
      const badJson = r'{"data":[["01/05/2026","2.70"]]}';
      final rates = CbttProvider.parseCbttJson(badJson);
      expect(rates, isNull);
    });
  });

  group('CBTT Provider live test', () {
    test('fetchRates returns rates with EUR present', () async {
      final provider = CbttProvider();
      final rates = await provider.fetchRates();

      // The site may block server IPs; allow null gracefully.
      if (rates == null) {
        print('CBTT live fetch returned null (likely bot/IP blocking)');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('CAD'), isTrue);
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates.containsKey('TTD'), isTrue);
      expect(rates['TTD'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
