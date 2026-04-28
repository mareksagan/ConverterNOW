import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

abstract class CurrencyProvider {
  String get id;
  String get name;

  Future<Map<String, double>?> fetchRates();

  /// The list of currencies this provider is expected to support.
  /// Used to filter out stale or obsolete currencies from saved data.
  List<String> get supportedCurrencies;
}

/// Normalizes rates to EUR base.
/// [rawRates] must contain rates in the provider's base currency
/// (providerBase per unit of foreign currency).
/// Returns a map where EUR = 1 and other currencies are relative to EUR.
Map<String, double> _normalizeToEurBase(
  Map<String, double> rawRates,
) {
  final eurRate = rawRates['EUR'];
  if (eurRate == null || eurRate == 0) return {};

  final normalized = <String, double>{};
  for (final entry in rawRates.entries) {
    normalized[entry.key] = eurRate / entry.value;
  }
  normalized['EUR'] = 1.0;
  return normalized;
}

class EcbProvider implements CurrencyProvider {
  @override
  String get id => 'ecb';

  @override
  String get name => 'European Central Bank';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'data-api.ecb.europa.eu',
        'service/data/EXR/D..EUR.SP00.A',
        {'lastNObservations': '1', 'detail': 'dataonly', 'format': 'csvdata'},
      ),
    );

    if (response.statusCode == 200) {
      Map<String, double> exchangeRates = {'EUR': 1};
      final rows = const LineSplitter().convert(response.body);
      final tableHeader = rows[0].split(',');
      final valueIndex = tableHeader.indexOf('OBS_VALUE');
      final currencyIndex = tableHeader.indexOf('CURRENCY');
      final dateIndex = tableHeader.indexOf('TIME_PERIOD');
      rows.removeAt(0);
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      for (var row in rows) {
        if (row.trim().isEmpty) continue;
        final elements = row.split(',');
        if (elements.length <= currencyIndex || elements.length <= valueIndex) continue;
        final currency = elements[currencyIndex];
        final value = double.tryParse(elements[valueIndex]);
        if (value == null) continue;
        // Skip obsolete currencies (last observation older than 90 days)
        if (dateIndex >= 0 && dateIndex < elements.length) {
          try {
            final obsDate = DateTime.parse(elements[dateIndex]);
            if (obsDate.isBefore(cutoff)) continue;
          } catch (_) {}
        }
        exchangeRates[currency] = value;
      }
      return exchangeRates;
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BGN', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR',
    'GBP', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW',
    'MXN', 'MYR', 'NOK', 'NZD', 'PHP', 'PLN', 'RON', 'SEK', 'SGD',
    'THB', 'TRY', 'USD', 'ZAR',
  ];
}

class NorgesBankProvider implements CurrencyProvider {
  @override
  String get id => 'norges_bank';

  @override
  String get name => 'Norges Bank';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'data.norges-bank.no',
        '/api/data/EXR/B..NOK.SP',
        {'lastNObservations': '1', 'format': 'sdmx-compact-2.1'},
      ),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};
      final document = XmlDocument.parse(response.body);

      // Find all Series elements
      for (final series in document.findAllElements('Series')) {
        final baseCur = series.getAttribute('BASE_CUR');
        final unitMult = series.getAttribute('UNIT_MULT');
        if (baseCur == null) continue;

        final multiplier = int.tryParse(unitMult ?? '0') ?? 0;
        final multiplierValue = multiplier > 0 ? multiplier : 1;

        // Find the latest Obs in this series
        final observations = series.findElements('Obs').toList();
        if (observations.isEmpty) continue;

        final latestObs = observations.last;
        final valueStr = latestObs.getAttribute('OBS_VALUE');
        if (valueStr == null) continue;

        final value = double.tryParse(valueStr);
        if (value == null || value == 0) continue;

        // value is NOK per unit of foreign currency
        // We want raw rate = NOK per unit
        rawRates[baseCur] = value * multiplierValue;
      }

      // NOK itself is implicitly 1 NOK per NOK
      rawRates['NOK'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BDT', 'BGN', 'BRL', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK',
    'EUR', 'GBP', 'HKD', 'HRK', 'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY',
    'KRW', 'MMK', 'MXN', 'MYR', 'NOK', 'NZD', 'PHP', 'PKR', 'PLN', 'RON',
    'RUB', 'SEK', 'SGD', 'THB', 'TRY', 'TWD', 'USD', 'VND', 'XDR', 'ZAR',
  ];
}

class BankRossiiProvider implements CurrencyProvider {
  @override
  String get id => 'bank_rossii';

  @override
  String get name => 'Bank Rossii';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https('www.cbr.ru', '/scripts/XML_daily.asp'),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};
      final document = XmlDocument.parse(response.body);

      for (final valute in document.findAllElements('Valute')) {
        final charCode = valute.findElements('CharCode').firstOrNull?.innerText;
        final vunitRate = valute.findElements('VunitRate').firstOrNull?.innerText ??
            valute.findElements('Value').firstOrNull?.innerText;

        if (charCode == null || vunitRate == null) continue;

        final value = double.tryParse(vunitRate.replaceAll(',', '.'));
        if (value == null || value == 0) continue;

        // VunitRate is RUB per unit of foreign currency
        rawRates[charCode] = value;
      }

      // RUB itself
      rawRates['RUB'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AMD', 'AUD', 'AZN', 'BDT', 'BHD', 'BOB', 'BRL', 'BYN', 'CAD',
    'CHF', 'CNY', 'CUP', 'CZK', 'DKK', 'DZD', 'EGP', 'ETB', 'EUR', 'GBP',
    'GEL', 'HKD', 'HUF', 'IDR', 'INR', 'IRR', 'JPY', 'KGS', 'KRW', 'KZT',
    'MDL', 'MMK', 'MNT', 'NGN', 'NOK', 'NZD', 'OMR', 'PLN', 'QAR', 'RON',
    'RSD', 'RUB', 'SAR', 'SEK', 'SGD', 'THB', 'TJS', 'TMT', 'TRY', 'UAH',
    'USD', 'UZS', 'VND', 'XDR', 'ZAR',
  ];
}

class BankOfCanadaProvider implements CurrencyProvider {
  @override
  String get id => 'bank_of_canada';

  @override
  String get name => 'Bank of Canada';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'www.bankofcanada.ca',
        '/valet/observations/group/FX_RATES_DAILY_CURRENT/json',
        {'recent': '1', 'order_dir': 'desc'},
      ),
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);

      // Check for error message
      if (jsonData['message'] != null) return null;

      final observations = jsonData['observations'];
      if (observations == null || observations is! List || observations.isEmpty) {
        return null;
      }

      final latest = observations[0];
      final rawRates = <String, double>{};

      for (final key in latest.keys) {
        if (key == 'd') continue; // date field
        if (key.length < 5 || !key.startsWith('FX')) continue;

        final currency = key.substring(2, 5);
        final valueData = latest[key];
        if (valueData is! Map || valueData['v'] == null) continue;

        final value = double.tryParse(valueData['v'].toString());
        if (value == null || value == 0) continue;

        // value is CAD per unit of foreign currency
        rawRates[currency] = value;
      }

      // CAD itself
      rawRates['CAD'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD', 'IDR', 'INR', 'JPY',
    'KRW', 'MXN', 'NOK', 'NZD', 'PEN', 'RUB', 'SAR', 'SEK', 'SGD', 'TRY',
    'TWD', 'USD', 'ZAR',
  ];
}

class InforEuroProvider implements CurrencyProvider {
  @override
  String get id => 'inforeuro';

  @override
  String get name => 'InforEuro';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'ec.europa.eu',
        '/budg/inforeuro/api/public/monthly-rates',
      ),
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      if (jsonData is List) {
        final exchangeRates = <String, double>{};
        for (final item in jsonData) {
          if (item is Map) {
            final currency = item['isoA3Code'] as String?;
            final value = item['value'] as num?;
            if (currency != null && value != null) {
              exchangeRates[currency] = value.toDouble();
            }
          }
        }
        return exchangeRates;
      }
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'ALL', 'AMD', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', 'BAM',
    'BBD', 'BDT', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL', 'BSD', 'BTN',
    'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY', 'COP', 'CRC',
    'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB',
    'EUR', 'FJD', 'FKP', 'GBP', 'GEL', 'GHS', 'GIP', 'GMD', 'GNF', 'GTQ',
    'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR',
    'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF', 'KRW', 'KWD',
    'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL',
    'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK', 'MXN',
    'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB',
    'PEN', 'PGK', 'PHP', 'PKR', 'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB',
    'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE', 'SOS',
    'SRD', 'SSP', 'STN', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP',
    'TRY', 'TTD', 'TWD', 'TZS', 'UAH', 'UGX', 'USD', 'UYU', 'UZS', 'VES',
    'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XCG', 'XOF', 'XPF', 'YER', 'ZAR',
    'ZIG', 'ZMW',
  ];
}

final List<CurrencyProvider> currencyProviders = [
  InforEuroProvider(),
  EcbProvider(),
  NorgesBankProvider(),
  BankRossiiProvider(),
  BankOfCanadaProvider(),
];

CurrencyProvider getCurrencyProviderById(String id) {
  return currencyProviders.firstWhere(
    (p) => p.id == id,
    orElse: () => currencyProviders.first,
  );
}
