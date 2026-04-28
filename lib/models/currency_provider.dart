import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

abstract class CurrencyProvider {
  String get id;
  String get name;

  /// Short initials of the provider, used in the last-update display.
  String get initials;

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
  String get initials => 'ECB';

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
  String get initials => 'NB';

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
  String get initials => 'CBR';

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
  String get initials => 'BOC';

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

class BcbProvider implements CurrencyProvider {
  @override
  String get id => 'bcb_bolivia';

  @override
  String get name => 'Banco Central de Bolivia';

  @override
  String get initials => 'BCB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'www.bcb.gob.bo',
        '/librerias/indicadores/otras/ultimo.php',
      ),
    );

    if (response.statusCode == 200) {
      final rowRegExp = RegExp(
        r'<tr class="listas-fila[12]">(.*?)</tr>',
        caseSensitive: false,
        dotAll: true,
      );

      final cellRegExp = RegExp(
        r'<td[^>]*>.*?<div[^>]*>\s*(.*?)\s*</div>.*?</td>',
        caseSensitive: false,
        dotAll: true,
      );

      final rawRates = <String, double>{};

      for (final rowMatch in rowRegExp.allMatches(response.body)) {
        final row = rowMatch.group(1)!;
        final cells = cellRegExp.allMatches(row).map((m) {
          var text = m.group(1)!.trim();
          text = text.replaceAll('&nbsp;', ' ').trim();
          return text;
        }).toList();

        if (cells.length < 4) continue;

        var currency = cells[2];
        final rateStr = cells[3];

        // Skip empty rates
        if (rateStr.isEmpty || rateStr == ' ') continue;

        // Handle USD.VENTA / USD.COMPRA
        if (currency == 'USD.VENTA') {
          currency = 'USD';
        } else if (currency.contains('.COMPRA') || currency.contains('.')) {
          continue;
        }

        // Skip non-standard currencies
        if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) continue;

        // Parse rate - remove comma thousands separator
        final cleanRateStr = rateStr.replaceAll(',', '');
        final rate = double.tryParse(cleanRateStr);
        if (rate == null || rate == 0) continue;

        // Don't overwrite existing currency (e.g. skip Ecuador's USD after USD.VENTA)
        if (rawRates.containsKey(currency)) continue;

        rawRates[currency] = rate;
      }

      // BOB itself
      rawRates['BOB'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'ARS', 'AUD', 'BRL', 'CAD', 'CHF', 'CLP', 'CNH', 'CNY', 'COP',
    'CRC', 'CZK', 'DKK', 'DOP', 'DZD', 'EUR', 'GBP', 'HKD', 'HTG', 'IDR',
    'ILS', 'INR', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK', 'PAB', 'PEN', 'PHP',
    'PYG', 'RUB', 'SAR', 'SEK', 'SGD', 'THB', 'TND', 'TRY', 'TWD', 'USD',
    'UYU', 'VES', 'VND', 'ZAR', 'BOB',
  ];
}

class RiksbankProvider implements CurrencyProvider {
  @override
  String get id => 'riksbank';

  @override
  String get name => 'Sveriges Riksbank';

  @override
  String get initials => 'SR';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final now = DateTime.now();
    final to = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final fromDate = now.subtract(const Duration(days: 7));
    final from = '${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}-${fromDate.day.toString().padLeft(2, '0')}';

    final response = await http.get(
      Uri.https(
        'www.riksbank.se',
        '/en-gb/statistics/interest-rates-and-exchange-rates/search-interest-rates-and-exchange-rates/',
        {
          's': [
            'g130-SEKAUDPMI', 'g130-SEKBRLPMI', 'g130-SEKCADPMI',
            'g130-SEKCHFPMI', 'g130-SEKCNYPMI', 'g130-SEKCZKPMI',
            'g130-SEKDKKPMI', 'g130-SEKEURPMI', 'g130-SEKGBPPMI',
            'g130-SEKHKDPMI', 'g130-SEKHUFPMI', 'g130-SEKIDRPMI',
            'g130-SEKILSPMI', 'g130-SEKINRPMI', 'g130-SEKISKPMI',
            'g130-SEKJPYPMI', 'g130-SEKKRWPMI', 'g130-SEKMXNPMI',
            'g130-SEKMYRPMI', 'g130-SEKRONPMI', 'g130-SEKNOKPMI',
            'g130-SEKNZDPMI', 'g130-SEKPHPPMI', 'g130-SEKPLNPMI',
            'g130-SEKSGDPMI', 'g130-SEKTHBPMI', 'g130-SEKTRYPMI',
            'g130-SEKUSDPMI', 'g130-SEKZARPMI',
          ],
          'a': 'D',
          'from': from,
          'to': to,
          'fs': '3',
          'd': ['Comma', 'Comma'],
          'export': 'txt',
        },
      ),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};
      final latestDates = <String, DateTime>{};
      final lines = const LineSplitter().convert(response.body);

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final columns = line.split('\t');
        if (columns.length < 4) continue;

        final dateStr = columns[0].trim();
        final series = columns[2].trim();
        final valueStr = columns[3].trim();

        // Parse date (DD/MM/YYYY)
        final dateParts = dateStr.split('/');
        if (dateParts.length != 3) continue;
        final date = DateTime(
          int.tryParse(dateParts[2]) ?? 0,
          int.tryParse(dateParts[1]) ?? 0,
          int.tryParse(dateParts[0]) ?? 0,
        );

        // Extract currency from "1 AUD"
        if (!series.startsWith('1 ')) continue;
        final currency = series.substring(2).trim();
        if (currency.length != 3) continue;

        // Parse value - comma is decimal separator
        final cleanValueStr = valueStr.replaceAll(',', '.');
        final value = double.tryParse(cleanValueStr);
        if (value == null || value == 0) continue;

        // Keep only the latest rate for each currency
        final existingDate = latestDates[currency];
        if (existingDate == null || date.isAfter(existingDate)) {
          latestDates[currency] = date;
          rawRates[currency] = value;
        }
      }

      if (rawRates.isEmpty) return null;

      // SEK itself
      rawRates['SEK'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HKD',
    'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK',
    'NZD', 'PHP', 'PLN', 'RON', 'SEK', 'SGD', 'THB', 'TRY', 'USD', 'ZAR',
  ];
}

class NbpProvider implements CurrencyProvider {
  @override
  String get id => 'nbp';

  @override
  String get name => 'Narodowy Bank Polski';

  @override
  String get initials => 'NBP';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'static.nbp.pl',
        '/dane/kursy/xml/LastA.xml',
      ),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};
      final document = XmlDocument.parse(response.body);

      for (final pozycja in document.findAllElements('pozycja')) {
        final kodWaluty = pozycja.findElements('kod_waluty').firstOrNull?.innerText;
        final kursSredni = pozycja.findElements('kurs_sredni').firstOrNull?.innerText;
        final przelicznik = pozycja.findElements('przelicznik').firstOrNull?.innerText;

        if (kodWaluty == null || kursSredni == null || przelicznik == null) {
          continue;
        }

        final multiplier = int.tryParse(przelicznik);
        final rate = double.tryParse(kursSredni.replaceAll(',', '.'));
        if (multiplier == null || multiplier == 0 || rate == null || rate == 0) {
          continue;
        }

        // kurs_sredni is PLN per <przelicznik> units of foreign currency
        rawRates[kodWaluty] = rate / multiplier;
      }

      if (rawRates.isEmpty) return null;

      // PLN itself
      rawRates['PLN'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CLP', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP',
    'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR',
    'NOK', 'NZD', 'PHP', 'PLN', 'RON', 'SEK', 'SGD', 'THB', 'TRY', 'UAH',
    'USD', 'XDR', 'ZAR',
  ];
}

class DanmarksNationalbankProvider implements CurrencyProvider {
  @override
  String get id => 'danmarks_nationalbank';

  @override
  String get name => 'Danmarks Nationalbank';

  @override
  String get initials => 'DN';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'www.nationalbanken.dk',
        '/api/currencyrates',
        {
          'lang': 'da',
          'isoCodes':
              'USD,AUD,BRL,GBP,CAD,EUR,PHP,HKD,INR,IDR,ISK,ILS,JPY,CNY,MYR,MXN,NZD,NOK,PLN,RON,CHF,SGD,SEK,ZAR,KRW,THB,CZK,TRY,HUF,XDR',
          'span': '2',
        },
      ),
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      final ratesList = jsonData['currencyRatesList'];
      if (ratesList == null || ratesList is! List) return null;

      final rawRates = <String, double>{};
      final latestDates = <String, DateTime>{};

      for (final item in ratesList) {
        if (item is! Map) continue;

        final currency = item['currency'];
        if (currency is! Map) continue;

        final isoCode = currency['isoCode'] as String?;
        final rateValue = item['rate'] as num?;
        final dateStr = item['date'] as String?;

        if (isoCode == null || rateValue == null || dateStr == null) continue;

        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;

        // Rate is DKK per 100 units of foreign currency
        final rate = rateValue.toDouble() / 100.0;
        if (rate == 0) continue;

        // Keep only the latest rate for each currency
        final existingDate = latestDates[isoCode];
        if (existingDate == null || date.isAfter(existingDate)) {
          latestDates[isoCode] = date;
          rawRates[isoCode] = rate;
        }
      }

      if (rawRates.isEmpty) return null;

      // DKK itself
      rawRates['DKK'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HKD',
    'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK',
    'NZD', 'PHP', 'PLN', 'RON', 'SEK', 'SGD', 'THB', 'TRY', 'USD', 'XDR',
    'ZAR',
  ];
}

class BnrProvider implements CurrencyProvider {
  @override
  String get id => 'bnr';

  @override
  String get name => 'Banca Națională a României';

  @override
  String get initials => 'BNR';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https('curs.bnr.ro', '/nbrfxrates.xml'),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};
      final document = XmlDocument.parse(response.body);

      for (final rateElem in document.findAllElements('Rate')) {
        final currency = rateElem.getAttribute('currency');
        final multiplier = rateElem.getAttribute('multiplier');
        final valueStr = rateElem.innerText;

        if (currency == null || valueStr.isEmpty) continue;
        // Skip gold (not a currency)
        if (currency == 'XAU') continue;

        final mult = int.tryParse(multiplier ?? '1') ?? 1;
        final value = double.tryParse(valueStr);
        if (mult == 0 || value == null || value == 0) continue;

        // Rate is RON per <multiplier> units of foreign currency
        rawRates[currency] = value / mult;
      }

      if (rawRates.isEmpty) return null;

      // RON itself
      rawRates['RON'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EGP', 'EUR',
    'GBP', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MDL',
    'MXN', 'MYR', 'NOK', 'NZD', 'PHP', 'PLN', 'RON', 'RSD', 'RUB', 'SEK',
    'SGD', 'THB', 'TRY', 'UAH', 'USD', 'XDR', 'ZAR',
  ];
}

class BancaDItaliaProvider implements CurrencyProvider {
  @override
  String get id => 'banca_ditalia';

  @override
  String get name => "Banca d'Italia";

  @override
  String get initials => 'BI';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'tassidicambio.bancaditalia.it',
        '/terzevalute-wf-web/rest/v1.0/latestRates',
        {'lang': 'en'},
      ),
    );

    if (response.statusCode == 200) {
      final jsonData = jsonDecode(response.body);
      final ratesList = jsonData['latestRates'];
      if (ratesList == null || ratesList is! List) return null;

      final exchangeRates = <String, double>{};
      for (final item in ratesList) {
        if (item is! Map) continue;
        final isoCode = item['isoCode'] as String?;
        final eurRate = item['eurRate'] as String?;
        if (isoCode == null || eurRate == null) continue;

        final value = double.tryParse(eurRate);
        if (value == null || value == 0) continue;

        exchangeRates[isoCode] = value;
      }

      exchangeRates['EUR'] = 1.0;
      return exchangeRates;
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HKD',
    'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK',
    'NZD', 'PHP', 'PLN', 'RON', 'RUB', 'SEK', 'SGD', 'THB', 'TRY', 'USD',
    'ZAR',
  ];
}

class RbaProvider implements CurrencyProvider {
  @override
  String get id => 'rba';

  @override
  String get name => 'Reserve Bank of Australia';

  @override
  String get initials => 'RBA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final response = await http.get(
      Uri.https(
        'www.rba.gov.au',
        '/statistics/frequency/exchange-rates.html',
      ),
    );

    if (response.statusCode == 200) {
      final rawRates = <String, double>{};

      final rowRegExp = RegExp(
        r'<tr\s+id="([A-Z][A-Z0-9_]*)"\s*[^>]*>(.*?)</tr>',
        caseSensitive: false,
        dotAll: true,
      );

      final cellRegExp = RegExp(
        r'<td[^>]*class="highlight"[^>]*>\s*(?:<[^>]+>)?\s*([\d.]+)\s*(?:</[^>]+>)?\s*</td>',
        caseSensitive: false,
        dotAll: true,
      );

      for (final rowMatch in rowRegExp.allMatches(response.body)) {
        final id = rowMatch.group(1)!;
        final rowContent = rowMatch.group(2)!;

        // Skip the trade-weighted index (not a currency)
        if (id == 'TWI_4pm') continue;

        final cellMatch = cellRegExp.firstMatch(rowContent);
        if (cellMatch == null) continue;

        final rateStr = cellMatch.group(1)!;
        final rate = double.tryParse(rateStr);
        if (rate == null || rate == 0) continue;

        var currency = id;
        if (currency == 'SDR') currency = 'XDR';

        rawRates[currency] = rate;
      }

      if (rawRates.isEmpty) return null;

      // AUD itself
      rawRates['AUD'] = 1.0;

      return _normalizeToEurBase(rawRates);
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD', 'IDR', 'INR', 'JPY',
    'KRW', 'MYR', 'NZD', 'PGK', 'PHP', 'SGD', 'THB', 'TWD', 'USD', 'VND',
    'XDR',
  ];
}

class MasProvider implements CurrencyProvider {
  @override
  String get id => 'mas';

  @override
  String get name => 'Monetary Authority of Singapore';

  @override
  String get initials => 'MAS';

  static const _url = 'https://eservices.mas.gov.sg/Statistics/msb/ExchangeRates.aspx';

  @override
  Future<Map<String, double>?> fetchRates() async {
    // Step 1: GET the page to extract ASP.NET form tokens
    final getResponse = await http.get(Uri.parse(_url));
    if (getResponse.statusCode != 200) return null;

    final body = getResponse.body;
    final viewState = _extractHiddenField(body, '__VIEWSTATE');
    final viewStateGenerator = _extractHiddenField(body, '__VIEWSTATEGENERATOR');
    final eventValidation = _extractHiddenField(body, '__EVENTVALIDATION');

    if (viewState == null || viewStateGenerator == null || eventValidation == null) {
      return null;
    }

    // Step 2: POST with extracted tokens to download rates
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString();
    // Also request previous month to ensure we get data even if current month is empty
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;

    final formData = <String, String>{
      '__VIEWSTATE': viewState,
      '__VIEWSTATEGENERATOR': viewStateGenerator,
      '__EVENTVALIDATION': eventValidation,
      'ctl00\$ContentPlaceHolder1\$StartYearDropDownList': prevYear.toString(),
      'ctl00\$ContentPlaceHolder1\$EndYearDropDownList': year,
      'ctl00\$ContentPlaceHolder1\$StartMonthDropDownList': prevMonth.toString(),
      'ctl00\$ContentPlaceHolder1\$EndMonthDropDownList': month,
      'ctl00\$ContentPlaceHolder1\$FrequencyDropDownList': 'D',
      'ctl00\$ContentPlaceHolder1\$DownloadButton': 'Download',
      // Per-unit currencies: EUR, GBP, USD
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPerUnitCheckBoxList\$0': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPerUnitCheckBoxList\$1': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPerUnitCheckBoxList\$2': 'on',
      // Per-100-unit currencies: AUD, CAD, CNY, HKD, INR, IDR, JPY, KRW,
      // MYR, TWD, NZD, PHP, QAR, SAR, CHF, THB, AED, VND
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$0': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$1': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$2': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$3': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$4': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$5': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$6': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$7': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$8': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$9': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$10': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$11': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$12': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$13': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$14': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$15': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$16': 'on',
      'ctl00\$ContentPlaceHolder1\$EndOfPeriodPer100UnitsCheckBoxList\$17': 'on',
    };

    final postResponse = await http.post(
      Uri.parse(_url),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': _url,
      },
      body: formData.entries.map((e) {
        return '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}';
      }).join('&'),
    );

    if (postResponse.statusCode != 200) return null;

    return _parseMasResponse(postResponse.body);
  }

  String? _extractHiddenField(String html, String id) {
    final pattern = 'id="$id" value="';
    final start = html.indexOf(pattern);
    if (start == -1) return null;
    final valueStart = start + pattern.length;
    final valueEnd = html.indexOf('"', valueStart);
    if (valueEnd == -1) return null;
    return html.substring(valueStart, valueEnd);
  }

  Map<String, double>? _parseMasResponse(String body) {
    final lines = const LineSplitter().convert(body);

    // Find the header line and data rows
    int headerIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('End of Period')) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == -1 || headerIndex + 1 >= lines.length) return null;

    // Find the last non-empty data row
    String? lastDataRow;
    for (var i = lines.length - 1; i > headerIndex; i--) {
      final trimmed = lines[i].trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('*')) {
        lastDataRow = trimmed;
        break;
      }
    }
    if (lastDataRow == null) return null;

    final values = lastDataRow.split(',');
    // Expected: year, month, day, then 21 currency columns
    if (values.length < 24) return null;

    final rawRates = <String, double>{};

    // Helper to parse a rate at a given index
    void addRate(int index, String currency, {double divisor = 1.0}) {
      if (index < values.length) {
        final rate = double.tryParse(values[index].trim());
        if (rate != null && rate != 0) {
          rawRates[currency] = rate / divisor;
        }
      }
    }

    // Per-unit currencies (no divisor)
    addRate(3, 'EUR');
    addRate(4, 'GBP');
    addRate(5, 'USD');

    // Per-100-unit currencies (divide by 100)
    addRate(6, 'AUD', divisor: 100);
    addRate(7, 'CAD', divisor: 100);
    addRate(8, 'CNY', divisor: 100);
    addRate(9, 'HKD', divisor: 100);
    addRate(10, 'INR', divisor: 100);
    addRate(11, 'IDR', divisor: 100);
    addRate(12, 'JPY', divisor: 100);
    addRate(13, 'KRW', divisor: 100);
    addRate(14, 'MYR', divisor: 100);
    addRate(15, 'TWD', divisor: 100);
    addRate(16, 'NZD', divisor: 100);
    addRate(17, 'PHP', divisor: 100);
    addRate(18, 'QAR', divisor: 100);
    addRate(19, 'SAR', divisor: 100);
    addRate(20, 'CHF', divisor: 100);
    addRate(21, 'THB', divisor: 100);
    addRate(22, 'AED', divisor: 100);
    addRate(23, 'VND', divisor: 100);

    if (rawRates.isEmpty) return null;

    // SGD itself
    rawRates['SGD'] = 1.0;

    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD', 'IDR', 'INR',
    'JPY', 'KRW', 'MYR', 'NZD', 'PHP', 'QAR', 'SAR', 'SGD', 'THB', 'TWD',
    'USD', 'VND',
  ];
}

class InforEuroProvider implements CurrencyProvider {
  @override
  String get id => 'inforeuro';

  @override
  String get name => 'InforEuro';

  @override
  String get initials => 'IE';

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
  BcbProvider(),
  RiksbankProvider(),
  NbpProvider(),
  DanmarksNationalbankProvider(),
  BnrProvider(),
  BancaDItaliaProvider(),
  RbaProvider(),
  MasProvider(),
];

CurrencyProvider getCurrencyProviderById(String id) {
  return currencyProviders.firstWhere(
    (p) => p.id == id,
    orElse: () => currencyProviders.first,
  );
}
