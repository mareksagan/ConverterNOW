import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleJson = r'''
{
  "jsonapi": {"version": "1.1"},
  "data": [{
    "type": "node--exchange_rates",
    "id": "test-node",
    "attributes": {
      "field_average_exchange_rate_date": "2026-05-04"
    },
    "relationships": {
      "field_average_exchange_rates": {
        "data": [
          {"type": "paragraph--zmw_usd", "id": "p-usd"},
          {"type": "paragraph--zmw_gbp", "id": "p-gbp"},
          {"type": "paragraph--zmw_euro", "id": "p-eur"},
          {"type": "paragraph--zmw_zar", "id": "p-zar"}
        ]
      }
    }
  }],
  "included": [
    {
      "type": "paragraph--zmw_usd",
      "id": "p-usd",
      "attributes": {
        "currency": "USD",
        "buying": "18.7471",
        "selling": "18.7971"
      }
    },
    {
      "type": "paragraph--zmw_gbp",
      "id": "p-gbp",
      "attributes": {
        "currency": "GBP",
        "buying": "25.4211",
        "selling": "25.4983"
      }
    },
    {
      "type": "paragraph--zmw_euro",
      "id": "p-eur",
      "attributes": {
        "currency": "EUR",
        "buying": "21.9623",
        "selling": "22.0246"
      }
    },
    {
      "type": "paragraph--zmw_zar",
      "id": "p-zar",
      "attributes": {
        "currency": "ZAR",
        "buying": "1.1228",
        "selling": "1.1261"
      }
    }
  ]
}
''';

void main() {
  group('BozProvider', () {
    test('id, name and initials are correct', () {
      final p = BozProvider();
      expect(p.id, 'boz');
      expect(p.name, 'Bank of Zambia');
      expect(p.initials, 'BoZ');
    });

    test('parseBozJson computes mid rates from buying and selling', () {
      final rates = BozProvider.parseBozJson(_sampleJson);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(21.99345, 0.0001));
      expect(rates['USD'], closeTo(18.7721, 0.0001));
      expect(rates['GBP'], closeTo(25.4597, 0.0001));
      expect(rates['ZAR'], closeTo(1.12445, 0.0001));
    });

    test('parseBozJson returns null for missing EUR', () {
      final json = _sampleJson.replaceAll('"currency": "EUR"', '"currency": "XXX"');
      expect(BozProvider.parseBozJson(json), isNull);
    });

    test('parseBozJson returns null for empty data', () {
      expect(BozProvider.parseBozJson('{"data": []}'), isNull);
    });

    test('parseBozJson returns null for empty included', () {
      expect(BozProvider.parseBozJson('{"data": [{}], "included": []}'), isNull);
    });

    test('fetchRates returns EUR-based rates', () async {
      final rates = await BozProvider().fetchRates();
      if (rates == null) {
        print('BoZ live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('GBP'), isTrue);
      expect(rates.containsKey('ZAR'), isTrue);
      expect(rates.containsKey('ZMW'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
