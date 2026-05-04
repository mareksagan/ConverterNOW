import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BomProvider', () {
    late BomProvider provider;

    setUp(() {
      provider = BomProvider();
    });

    test('parseBomJson returns normalized rates', () {
      const sampleJson = r'''
      {
        "success": true,
        "data": [
          {
            "RATE_DATE": "2026-04-29",
            "USD": "3,576.14",
            "EUR": "4,186.05",
            "JPY": "22.40"
          },
          {
            "RATE_DATE": "2026-04-30",
            "USD": "3,576.22",
            "EUR": "4,177.02",
            "JPY": "22.33",
            "GBP": "4,823.07",
            "CNY": "523.23",
            "RUB": "47.58"
          }
        ]
      }
      ''';

      final rates = provider.parseBomJson(sampleJson);

      expect(rates, isNotNull);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));

      // EUR = 4177.02, USD = 3576.22
      // normalized USD = 4177.02 / 3576.22 ≈ 1.168
      expect(rates['USD'], closeTo(1.168, 0.001));

      // EUR = 4177.02, JPY = 22.33
      // normalized JPY = 4177.02 / 22.33 ≈ 187.1
      expect(rates['JPY'], closeTo(187.1, 0.5));

      // EUR = 4177.02, MNT = 1.0
      // normalized MNT = 4177.02 / 1.0 = 4177.02
      expect(rates['MNT'], closeTo(4177.02, 0.01));

      expect(rates.containsKey('GBP'), isTrue);
      expect(rates.containsKey('CNY'), isTrue);
      expect(rates.containsKey('RUB'), isTrue);
    });

    test('parseBomJson handles empty data', () {
      const emptyJson = '{"success": true, "data": []}';
      expect(provider.parseBomJson(emptyJson), isNull);
    });

    test('parseBomJson handles missing data field', () {
      const badJson = '{"success": true}';
      expect(provider.parseBomJson(badJson), isNull);
    });

    test('fetchRates smoke test (live API)', () async {
      final rates = await provider.fetchRates();
      if (rates != null) {
        expect(rates.containsKey('EUR'), isTrue);
        expect(rates.containsKey('USD'), isTrue);
        expect(rates.containsKey('MNT'), isTrue);
        expect(rates['EUR'], closeTo(1.0, 0.0001));
      }
    }, timeout: Timeout(Duration(seconds: 30)));
  });
}
