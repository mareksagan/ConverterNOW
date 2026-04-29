import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

/// Some central banks use regional CAs (e.g. Certum, Actalis) that are not
/// present in every Android trust store. This helper creates an HTTP client
/// that accepts certificates for those specific hosts.
http.Client _createPermissiveClient() {
  final context = SecurityContext(withTrustedRoots: true);
  final httpClient = HttpClient(context: context)
    ..badCertificateCallback = (cert, host, port) {
      return host == 'tassidicambio.bancaditalia.it' ||
          host == 'api.nbp.pl' ||
          host == 'static.nbp.pl';
    };
  return IOClient(httpClient);
}

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
    print('[NBP] Starting fetchRates()');
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.https(
          'api.nbp.pl',
          '/api/exchangerates/tables/A/',
          {'format': 'json'},
        ),
      ).timeout(const Duration(seconds: 15));
      client.close();

      print('[NBP] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List || jsonData.isEmpty) {
          print('[NBP] ERROR: jsonData is not a non-empty List');
          return null;
        }

        final table = jsonData[0];
        final ratesList = table['rates'];
        if (ratesList is! List) {
          print('[NBP] ERROR: ratesList is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final code = item['code'] as String?;
          final mid = item['mid'] as num?;
          if (code == null || mid == null) continue;
          if (mid == 0) continue;
          rawRates[code] = mid.toDouble();
        }

        print('[NBP] Parsed ${rawRates.length} raw rates');
        print('[NBP] Has EUR: ${rawRates.containsKey('EUR')}');
        print('[NBP] Has PLN: ${rawRates.containsKey('PLN')}');

        if (rawRates.isEmpty) {
          print('[NBP] ERROR: rawRates is empty');
          return null;
        }

        // PLN itself
        rawRates['PLN'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBP] Normalized rates count: ${normalized.length}');
        print('[NBP] Normalized EUR: ${normalized['EUR']}');
        print('[NBP] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBP] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBP] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBP] ERROR: $e');
      print('[NBP] Stack: $st');
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
    print('[BNR] Starting fetchRates()');
    try {
      // BNR publishes a yearly XML archive with all daily rates.
      // If the current year file isn't available yet (early January),
      // fall back to the previous year.
      final now = DateTime.now();
      final year = now.year;

      var response = await http.get(
        Uri.https('www.bnr.ro', '/files/xml/years/nbrfxrates$year.xml'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        print('[BNR] Year $year not available, trying ${year - 1}');
        response = await http.get(
          Uri.https('www.bnr.ro', '/files/xml/years/nbrfxrates${year - 1}.xml'),
        ).timeout(const Duration(seconds: 15));
      }

      print('[BNR] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final rawRates = <String, double>{};
        final document = XmlDocument.parse(response.body);

        // Find all <Cube date="..."> elements and pick the last one (most recent)
        final cubes = document.findAllElements('Cube').toList();
        print('[BNR] Found ${cubes.length} daily cubes');
        if (cubes.isEmpty) {
          print('[BNR] ERROR: No Cube elements found');
          return null;
        }

        final latestCube = cubes.last;
        final cubeDate = latestCube.getAttribute('date');
        print('[BNR] Latest cube date: $cubeDate');

        for (final rateElem in latestCube.findElements('Rate')) {
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

        print('[BNR] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        // RON itself
        rawRates['RON'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BNR] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BNR] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BNR] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BNR] ERROR: $e');
      print('[BNR] Stack: $st');
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
    print('[BI] Starting fetchRates()');
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.https(
          'tassidicambio.bancaditalia.it',
          '/terzevalute-wf-web/rest/v1.0/latestRates',
          {'lang': 'en'},
        ),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      client.close();

      print('[BI] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesList = jsonData['latestRates'];
        if (ratesList == null || ratesList is! List) {
          print('[BI] ERROR: ratesList is null or not a List');
          return null;
        }

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

        print('[BI] Parsed ${exchangeRates.length} rates');
        exchangeRates['EUR'] = 1.0;
        return exchangeRates;
      }
      print('[BI] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BI] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BI] ERROR: $e');
      print('[BI] Stack: $st');
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

  static const String _cbNamespace =
      'http://www.cbwiki.net/wiki/index.php/Specification_1.2/';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[RBA] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'www.rba.gov.au',
          '/rss/rss-cb-exchange-rates.xml',
        ),
      ).timeout(const Duration(seconds: 15));

      print('[RBA] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final rawRates = <String, double>{};
        final document = XmlDocument.parse(response.body);

        // The RSS feed uses CB (Central Bank) RSS 1.2 namespace.
        // Each currency is inside a <cb:exchangeRate> element with:
        //   <cb:targetCurrency>USD</cb:targetCurrency>
        //   <cb:observation><cb:value>0.7172</cb:value></cb:observation>
        for (final exchangeRate
            in document.findAllElements('exchangeRate', namespace: _cbNamespace)) {
          final targetCurrency = exchangeRate
              .findElements('targetCurrency', namespace: _cbNamespace)
              .firstOrNull
              ?.innerText;
          final value = exchangeRate
              .findElements('observation', namespace: _cbNamespace)
              .firstOrNull
              ?.findElements('value', namespace: _cbNamespace)
              .firstOrNull
              ?.innerText;

          if (targetCurrency == null || value == null) continue;

          // Skip the trade-weighted index (not a currency)
          if (targetCurrency == 'XXX') continue;

          final rate = double.tryParse(value);
          if (rate == null || rate == 0) continue;

          var currency = targetCurrency;
          if (currency == 'SDR') currency = 'XDR';

          rawRates[currency] = rate;
        }

        print('[RBA] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        // AUD itself
        rawRates['AUD'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[RBA] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[RBA] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[RBA] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[RBA] ERROR: $e');
      print('[RBA] Stack: $st');
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
    print('[MAS] Starting fetchRates()');
    try {
      // Step 1: GET the page to extract ASP.NET form tokens
      final getResponse = await http.get(
        Uri.parse(_url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 15));
      print('[MAS] GET status: ${getResponse.statusCode}, body len: ${getResponse.body.length}');
      if (getResponse.statusCode != 200) {
        print('[MAS] ERROR: GET failed with ${getResponse.statusCode}');
        return null;
      }

      final body = getResponse.body;
      final viewState = _extractHiddenField(body, '__VIEWSTATE');
      final viewStateGenerator = _extractHiddenField(body, '__VIEWSTATEGENERATOR');
      final eventValidation = _extractHiddenField(body, '__EVENTVALIDATION');

      print('[MAS] VIEWSTATE len: ${viewState?.length}');
      print('[MAS] VIEWSTATEGENERATOR: $viewStateGenerator');
      print('[MAS] EVENTVALIDATION len: ${eventValidation?.length}');

      if (viewState == null || viewStateGenerator == null || eventValidation == null) {
        print('[MAS] ERROR: Failed to extract one or more hidden fields');
        print('[MAS] Has VIEWSTATE: ${viewState != null}');
        print('[MAS] Has VIEWSTATEGENERATOR: ${viewStateGenerator != null}');
        print('[MAS] Has EVENTVALIDATION: ${eventValidation != null}');
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

      final encodedBody = formData.entries.map((e) {
        return '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}';
      }).join('&');

      print('[MAS] POST body length: ${encodedBody.length}');

      final postResponse = await http.post(
        Uri.parse(_url),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': _url,
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        body: encodedBody,
      ).timeout(const Duration(seconds: 15));

      print('[MAS] POST status: ${postResponse.statusCode}, body len: ${postResponse.body.length}');
      if (postResponse.statusCode != 200) {
        print('[MAS] ERROR: POST failed with ${postResponse.statusCode}');
        return null;
      }

      final result = _parseMasResponse(postResponse.body);
      print('[MAS] Parse result: ${result != null ? '${result.length} rates' : 'null'}');
      return result;
    } on TimeoutException catch (e) {
      print('[MAS] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[MAS] ERROR: $e');
      print('[MAS] Stack: $st');
    }
    return null;
  }

  String? _extractHiddenField(String html, String id) {
    // Try double-quoted id first
    var pattern = 'id="$id" value="';
    var start = html.indexOf(pattern);
    if (start == -1) {
      // Try single-quoted id
      pattern = "id='$id' value='";
      start = html.indexOf(pattern);
      if (start == -1) {
        // Try double-quoted id with single-quoted value
        pattern = 'id="$id" value=\'';
        start = html.indexOf(pattern);
      }
    }
    if (start == -1) return null;
    final valueStart = start + pattern.length;
    final quoteChar = pattern.endsWith("'") ? "'" : '"';
    final valueEnd = html.indexOf(quoteChar, valueStart);
    if (valueEnd == -1) return null;
    return html.substring(valueStart, valueEnd);
  }

  Map<String, double>? _parseMasResponse(String body) {
    final lines = const LineSplitter().convert(body);
    print('[MAS] Response has ${lines.length} lines');

    // Find the header line and data rows
    int headerIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('End of Period')) {
        headerIndex = i;
        break;
      }
    }
    print('[MAS] Header index: $headerIndex');
    if (headerIndex == -1 || headerIndex + 1 >= lines.length) {
      print('[MAS] ERROR: Could not find header line');
      return null;
    }

    // Find the last data row that has enough comma-separated values
    String? lastDataRow;
    for (var i = lines.length - 1; i > headerIndex; i--) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('*')) continue;
      final parts = trimmed.split(',');
      if (parts.length >= 24) {
        lastDataRow = trimmed;
        break;
      }
    }
    print('[MAS] Last data row: ${lastDataRow != null ? 'found' : 'not found'}');
    if (lastDataRow == null) {
      print('[MAS] ERROR: Could not find a valid data row with >=24 values');
      return null;
    }

    final values = lastDataRow.split(',');
    print('[MAS] Values count: ${values.length}');

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

    print('[MAS] Parsed ${rawRates.length} raw rates');
    if (rawRates.isEmpty) {
      print('[MAS] ERROR: rawRates is empty');
      return null;
    }

    // SGD itself
    rawRates['SGD'] = 1.0;

    final normalized = _normalizeToEurBase(rawRates);
    print('[MAS] Normalized rates count: ${normalized.length}');
    return normalized;
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

class BnmProvider implements CurrencyProvider {
  @override
  String get id => 'bnm';

  @override
  String get name => 'National Bank of Moldova';

  @override
  String get initials => 'BNM';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BNM] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

      final response = await http.get(
        Uri.https(
          'www.bnm.md',
          '/en/official_exchange_rates',
          {'date': dateStr},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[BNM] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final rawRates = <String, double>{};
        final document = XmlDocument.parse(response.body);

        for (final valute in document.findAllElements('Valute')) {
          final charCode = valute.findElements('CharCode').firstOrNull?.innerText;
          final nominalStr = valute.findElements('Nominal').firstOrNull?.innerText;
          final valueStr = valute.findElements('Value').firstOrNull?.innerText;

          if (charCode == null || valueStr == null) continue;

          final nominal = int.tryParse(nominalStr ?? '1') ?? 1;
          final value = double.tryParse(valueStr);
          if (nominal == 0 || value == null || value == 0) continue;

          // Rate is MDL per <nominal> units of foreign currency
          rawRates[charCode] = value / nominal;
        }

        print('[BNM] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        // MDL itself
        rawRates['MDL'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BNM] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BNM] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BNM] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BNM] ERROR: $e');
      print('[BNM] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'ALL', 'AMD', 'AUD', 'AZN', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK',
    'DKK', 'EUR', 'GBP', 'GEL', 'HKD', 'HUF', 'ILS', 'INR', 'ISK', 'JPY',
    'KGS', 'KRW', 'KWD', 'KZT', 'MDL', 'MKD', 'MYR', 'NOK', 'NZD', 'PLN',
    'RON', 'RSD', 'RUB', 'SEK', 'TJS', 'TMT', 'TRY', 'UAH', 'USD', 'UZS',
    'XDR',
  ];
}

class CnbProvider implements CurrencyProvider {
  @override
  String get id => 'cnb';

  @override
  String get name => 'Česká národní banka';

  @override
  String get initials => 'CNB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CNB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('api.cnb.cz', '/cnbapi/exrates/daily'),
      ).timeout(const Duration(seconds: 15));

      print('[CNB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesList = jsonData['rates'];
        if (ratesList is! List) {
          print('[CNB] ERROR: ratesList is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final code = item['currencyCode'] as String?;
          final rate = item['rate'] as num?;
          final amount = item['amount'] as num? ?? 1;
          if (code == null || rate == null || amount == 0) continue;
          rawRates[code] = rate.toDouble() / amount.toDouble();
        }

        print('[CNB] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CNB] ERROR: rawRates is empty');
          return null;
        }

        // CZK itself
        rawRates['CZK'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CNB] Normalized rates count: ${normalized.length}');
        print('[CNB] Normalized EUR: ${normalized['EUR']}');
        print('[CNB] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CNB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CNB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CNB] ERROR: $e');
      print('[CNB] Stack: $st');
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

class MnbProvider implements CurrencyProvider {
  @override
  String get id => 'mnb';

  @override
  String get name => 'Magyar Nemzeti Bank';

  @override
  String get initials => 'MNB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[MNB] Starting fetchRates()');
    try {
      final response = await http.post(
        Uri.http('www.mnb.hu', '/arfolyamok.asmx'),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction':
              'http://www.mnb.hu/webservices/MNBArfolyamServiceSoap/GetCurrentExchangeRates',
        },
        body:
            '<?xml version="1.0" encoding="utf-8"?>'
            '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
            '<soap:Body>'
            '<GetCurrentExchangeRates xmlns="http://www.mnb.hu/webservices/" />'
            '</soap:Body>'
            '</soap:Envelope>',
      ).timeout(const Duration(seconds: 15));

      print('[MNB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final resultElem = document
            .findAllElements('GetCurrentExchangeRatesResult')
            .firstOrNull;
        if (resultElem == null) {
          print('[MNB] ERROR: GetCurrentExchangeRatesResult not found');
          return null;
        }

        final innerXml = resultElem.innerText;
        if (innerXml.isEmpty) {
          print('[MNB] ERROR: innerXml is empty');
          return null;
        }

        final innerDoc = XmlDocument.parse(innerXml);
        final dayElem = innerDoc.findAllElements('Day').firstOrNull;
        if (dayElem == null) {
          print('[MNB] ERROR: Day element not found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final rateElem in dayElem.findElements('Rate')) {
          final code = rateElem.getAttribute('curr');
          final unitStr = rateElem.getAttribute('unit');
          final valueStr = rateElem.innerText;
          if (code == null || valueStr.isEmpty) continue;

          final unit = int.tryParse(unitStr ?? '1') ?? 1;
          // MNB uses comma as decimal separator
          final value = double.tryParse(valueStr.replaceAll(',', '.'));
          if (unit == 0 || value == null || value == 0) continue;

          rawRates[code] = value / unit;
        }

        print('[MNB] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[MNB] ERROR: rawRates is empty');
          return null;
        }

        // HUF itself
        rawRates['HUF'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[MNB] Normalized rates count: ${normalized.length}');
        print('[MNB] Normalized EUR: ${normalized['EUR']}');
        print('[MNB] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[MNB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[MNB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[MNB] ERROR: $e');
      print('[MNB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HKD',
    'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK',
    'NZD', 'PHP', 'PLN', 'RON', 'RSD', 'RUB', 'SEK', 'SGD', 'THB', 'TRY',
    'UAH', 'USD', 'ZAR',
  ];
}

class TcmbProvider implements CurrencyProvider {
  @override
  String get id => 'tcmb';

  @override
  String get name => 'Türkiye Cumhuriyet Merkez Bankası';

  @override
  String get initials => 'TCMB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[TCMB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('tcmb.gov.tr', '/kurlar/today.xml'),
      ).timeout(const Duration(seconds: 15));

      print('[TCMB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final currencies = document.findAllElements('Currency');
        if (currencies.isEmpty) {
          print('[TCMB] ERROR: No Currency elements found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final currency in currencies) {
          final code = currency.getAttribute('CurrencyCode');
          if (code == null) continue;

          final unitElem = currency.findElements('Unit').firstOrNull;
          final unit = int.tryParse(unitElem?.innerText.trim() ?? '1') ?? 1;

          // Use ForexBuying as the reference rate, fallback to ForexSelling
          var valueStr = currency.findElements('ForexBuying').firstOrNull?.innerText.trim();
          if (valueStr == null || valueStr.isEmpty) {
            valueStr = currency.findElements('ForexSelling').firstOrNull?.innerText.trim();
          }
          if (valueStr == null || valueStr.isEmpty) continue;

          final value = double.tryParse(valueStr);
          if (unit == 0 || value == null || value == 0) continue;

          rawRates[code] = value / unit;
        }

        print('[TCMB] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[TCMB] ERROR: rawRates is empty');
          return null;
        }

        // TRY itself
        rawRates['TRY'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[TCMB] Normalized rates count: ${normalized.length}');
        print('[TCMB] Normalized EUR: ${normalized['EUR']}');
        print('[TCMB] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[TCMB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[TCMB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[TCMB] ERROR: $e');
      print('[TCMB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'AZN', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'JPY',
    'KRW', 'KWD', 'KZT', 'NOK', 'PKR', 'QAR', 'RON', 'RUB', 'SAR', 'SEK',
    'TRY', 'USD', 'XDR',
  ];
}

class BccProvider implements CurrencyProvider {
  @override
  String get id => 'bcc';

  @override
  String get name => 'Banco Central de Cuba';

  @override
  String get initials => 'BCC';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCC] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('api.bc.gob.cu', '/v1/tasas-de-cambio/activas'),
      ).timeout(const Duration(seconds: 15));

      print('[BCC] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesList = jsonData['tasas'];
        if (ratesList is! List) {
          print('[BCC] ERROR: tasas is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final code = item['codigoMoneda'] as String?;
          final rate = item['tasaPublica'] as num?;
          if (code == null || rate == null || rate == 0) continue;
          rawRates[code] = rate.toDouble();
        }

        print('[BCC] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[BCC] ERROR: rawRates is empty');
          return null;
        }

        // CUP itself
        rawRates['CUP'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BCC] Normalized rates count: ${normalized.length}');
        print('[BCC] Normalized EUR: ${normalized['EUR']}');
        print('[BCC] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[BCC] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BCC] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCC] ERROR: $e');
      print('[BCC] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'CUP', 'DKK', 'EUR', 'GBP', 'JPY', 'MXN',
    'NOK', 'RUB', 'SEK', 'USD',
  ];
}

class BoiProvider implements CurrencyProvider {
  @override
  String get id => 'boi';

  @override
  String get name => 'Bank of Israel';

  @override
  String get initials => 'BOI';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BOI] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('boi.org.il', '/PublicApi/GetExchangeRates'),
      ).timeout(const Duration(seconds: 15));

      print('[BOI] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesList = jsonData['exchangeRates'];
        if (ratesList is! List) {
          print('[BOI] ERROR: exchangeRates is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final code = item['key'] as String?;
          final rate = item['currentExchangeRate'] as num?;
          final unit = item['unit'] as num? ?? 1;
          if (code == null || rate == null || unit == 0) continue;
          rawRates[code] = rate.toDouble() / unit.toDouble();
        }

        print('[BOI] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[BOI] ERROR: rawRates is empty');
          return null;
        }

        // ILS itself
        rawRates['ILS'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BOI] Normalized rates count: ${normalized.length}');
        print('[BOI] Normalized EUR: ${normalized['EUR']}');
        print('[BOI] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[BOI] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BOI] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOI] ERROR: $e');
      print('[BOI] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'DKK', 'EGP', 'EUR', 'GBP', 'ILS', 'JOD', 'JPY',
    'LBP', 'NOK', 'SEK', 'USD', 'ZAR',
  ];
}

class NbrkProvider implements CurrencyProvider {
  @override
  String get id => 'nbrk';

  @override
  String get name => 'National Bank of Republic Kazakhstan';

  @override
  String get initials => 'NBRK';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBRK] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
      final response = await http.get(
        Uri.https(
          'nationalbank.kz',
          '/rss/get_rates.cfm',
          {'fdate': dateStr},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[NBRK] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('item');
        if (items.isEmpty) {
          print('[NBRK] ERROR: No item elements found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in items) {
          final codeElem = item.findElements('title').firstOrNull;
          final rateElem = item.findElements('description').firstOrNull;
          final quantElem = item.findElements('quant').firstOrNull;

          final code = codeElem?.innerText.trim();
          final rateStr = rateElem?.innerText.trim();
          final quantStr = quantElem?.innerText.trim();

          if (code == null || rateStr == null || rateStr.isEmpty) continue;

          final quant = int.tryParse(quantStr ?? '1') ?? 1;
          final rate = double.tryParse(rateStr);
          if (quant == 0 || rate == null || rate == 0) continue;

          rawRates[code] = rate / quant;
        }

        print('[NBRK] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[NBRK] ERROR: rawRates is empty');
          return null;
        }

        // KZT itself
        rawRates['KZT'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBRK] Normalized rates count: ${normalized.length}');
        print('[NBRK] Normalized EUR: ${normalized['EUR']}');
        print('[NBRK] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBRK] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBRK] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBRK] ERROR: $e');
      print('[NBRK] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AMD', 'AUD', 'AZN', 'BRL', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK',
    'DKK', 'EUR', 'GBP', 'GEL', 'HKD', 'HUF', 'INR', 'IRR', 'JPY', 'KGS',
    'KRW', 'KWD', 'KZT', 'MDL', 'MXN', 'MYR', 'NOK', 'PLN', 'RUB', 'SAR',
    'SEK', 'SGD', 'THB', 'TJS', 'TRY', 'UAH', 'USD', 'UZS', 'XDR', 'ZAR',
  ];
}

class CbuProvider implements CurrencyProvider {
  @override
  String get id => 'cbu';

  @override
  String get name => "O'zbekiston Markaziy Banki";

  @override
  String get initials => 'CBU';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBU] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('cbu.uz', '/en/arkhiv-kursov-valyut/json/'),
      ).timeout(const Duration(seconds: 15));

      print('[CBU] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List) {
          print('[CBU] ERROR: response is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in jsonData) {
          if (item is! Map) continue;
          final code = item['Ccy'] as String?;
          final rateStr = item['Rate'] as String?;
          final nominalStr = item['Nominal'] as String?;
          if (code == null || rateStr == null) continue;

          final nominal = int.tryParse(nominalStr ?? '1') ?? 1;
          final rate = double.tryParse(rateStr);
          if (nominal == 0 || rate == null || rate == 0) continue;

          rawRates[code] = rate / nominal;
        }

        print('[CBU] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CBU] ERROR: rawRates is empty');
          return null;
        }

        // UZS itself
        rawRates['UZS'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBU] Normalized rates count: ${normalized.length}');
        print('[CBU] Normalized EUR: ${normalized['EUR']}');
        print('[CBU] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBU] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBU] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBU] ERROR: $e');
      print('[CBU] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'AMD', 'ARS', 'AUD', 'AZN', 'BDT', 'BHD', 'BND', 'BRL',
    'BYN', 'CAD', 'CHF', 'CNY', 'CUP', 'CZK', 'DKK', 'DZD', 'EGP', 'EUR',
    'GBP', 'GEL', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR', 'ISK',
    'JOD', 'JPY', 'KGS', 'KHR', 'KRW', 'KWD', 'KZT', 'LAK', 'LBP', 'LYD',
    'MAD', 'MDL', 'MMK', 'MNT', 'MXN', 'MYR', 'NOK', 'NZD', 'OMR', 'PHP',
    'PKR', 'PLN', 'QAR', 'RON', 'RSD', 'RUB', 'SAR', 'SDG', 'SEK', 'SGD',
    'SYP', 'THB', 'TJS', 'TMT', 'TND', 'TRY', 'UAH', 'USD', 'UYU', 'UZS',
    'VES', 'VND', 'XDR', 'YER', 'ZAR',
  ];
}

class NbuProvider implements CurrencyProvider {
  @override
  String get id => 'nbu';

  @override
  String get name => 'National Bank of Ukraine';

  @override
  String get initials => 'NBU';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBU] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('bank.gov.ua', '/NBU_Exchange/exchange'),
      ).timeout(const Duration(seconds: 15));

      print('[NBU] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final rows = document.findAllElements('ROW');
        if (rows.isEmpty) {
          print('[NBU] ERROR: No ROW elements found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final row in rows) {
          final codeElem = row.findElements('CurrencyCodeL').firstOrNull;
          final unitsElem = row.findElements('Units').firstOrNull;
          final amountElem = row.findElements('Amount').firstOrNull;

          final code = codeElem?.innerText.trim();
          final unitsStr = unitsElem?.innerText.trim();
          final amountStr = amountElem?.innerText.trim();

          if (code == null || amountStr == null || amountStr.isEmpty) continue;
          // Skip precious metals
          if (code == 'XAU' || code == 'XAG' || code == 'XPT' || code == 'XPD') {
            continue;
          }

          final units = int.tryParse(unitsStr ?? '1') ?? 1;
          final amount = double.tryParse(amountStr);
          if (units == 0 || amount == null || amount == 0) continue;

          rawRates[code] = amount / units;
        }

        print('[NBU] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[NBU] ERROR: rawRates is empty');
          return null;
        }

        // UAH itself
        rawRates['UAH'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBU] Normalized rates count: ${normalized.length}');
        print('[NBU] Normalized EUR: ${normalized['EUR']}');
        print('[NBU] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBU] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBU] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBU] ERROR: $e');
      print('[NBU] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'AZN', 'BDT', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'DZD',
    'EGP', 'EUR', 'GBP', 'GEL', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'JPY',
    'KRW', 'KZT', 'LBP', 'MDL', 'MXN', 'MYR', 'NOK', 'NZD', 'PLN', 'RON',
    'RSD', 'SAR', 'SEK', 'SGD', 'THB', 'TND', 'TRY', 'UAH', 'USD', 'VND',
    'ZAR',
  ];
}

class CbaProvider implements CurrencyProvider {
  @override
  String get id => 'cba';

  @override
  String get name => 'Central Bank of Armenia';

  @override
  String get initials => 'CBA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBA] Starting fetchRates()');
    try {
      final response = await http.post(
        Uri.https('api.cba.am', '/exchangerates.asmx'),
        headers: {
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'http://www.cba.am/ExchangeRatesLatest',
        },
        body:
            '<?xml version="1.0" encoding="utf-8"?>'
            '<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
            'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">'
            '<soap:Body>'
            '<ExchangeRatesLatest xmlns="http://www.cba.am/" />'
            '</soap:Body>'
            '</soap:Envelope>',
      ).timeout(const Duration(seconds: 15));

      print('[CBA] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final ratesElem = document.findAllElements('Rates').firstOrNull;
        if (ratesElem == null) {
          print('[CBA] ERROR: Rates element not found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final rateElem in ratesElem.findElements('ExchangeRate')) {
          final isoElem = rateElem.findElements('ISO').firstOrNull;
          final amountElem = rateElem.findElements('Amount').firstOrNull;
          final rateValueElem = rateElem.findElements('Rate').firstOrNull;

          final code = isoElem?.innerText.trim();
          final amountStr = amountElem?.innerText.trim();
          final rateStr = rateValueElem?.innerText.trim();

          if (code == null || rateStr == null || rateStr.isEmpty) continue;
          // Skip precious metals
          if (code == 'XAU' || code == 'XAG') continue;

          final amount = int.tryParse(amountStr ?? '1') ?? 1;
          final rate = double.tryParse(rateStr);
          if (amount == 0 || rate == null || rate == 0) continue;

          rawRates[code] = rate / amount;
        }

        print('[CBA] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CBA] ERROR: rawRates is empty');
          return null;
        }

        // AMD itself
        rawRates['AMD'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBA] Normalized rates count: ${normalized.length}');
        print('[CBA] Normalized EUR: ${normalized['EUR']}');
        print('[CBA] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBA] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBA] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBA] ERROR: $e');
      print('[CBA] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AMD', 'AUD', 'BRL', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK', 'EUR',
    'GBP', 'GEL', 'HKD', 'INR', 'IRR', 'JPY', 'KGS', 'KZT', 'NOK', 'NZD',
    'PLN', 'RUB', 'SEK', 'SGD', 'TJS', 'UAH', 'USD', 'UZS', 'XDR',
  ];
}

class NbgProvider implements CurrencyProvider {
  @override
  String get id => 'nbg';

  @override
  String get name => 'National Bank of Georgia';

  @override
  String get initials => 'NBG';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBG] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final response = await http.get(
        Uri.https(
          'nbg.gov.ge',
          '/gw/api/ct/monetarypolicy/currencies/en/json/',
          {'date': dateStr},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[NBG] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List || jsonData.isEmpty) {
          print('[NBG] ERROR: response is not a non-empty List');
          return null;
        }

        final ratesList = jsonData[0]['currencies'];
        if (ratesList is! List) {
          print('[NBG] ERROR: currencies is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final code = item['code'] as String?;
          final rate = item['rate'] as num?;
          final quantity = item['quantity'] as num? ?? 1;
          if (code == null || rate == null || quantity == 0) continue;
          rawRates[code] = rate.toDouble() / quantity.toDouble();
        }

        print('[NBG] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[NBG] ERROR: rawRates is empty');
          return null;
        }

        // GEL itself
        rawRates['GEL'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBG] Normalized rates count: ${normalized.length}');
        print('[NBG] Normalized EUR: ${normalized['EUR']}');
        print('[NBG] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBG] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBG] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBG] ERROR: $e');
      print('[NBG] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AMD', 'AUD', 'AZN', 'BRL', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK',
    'DKK', 'EGP', 'EUR', 'GBP', 'GEL', 'HKD', 'HUF', 'ILS', 'INR', 'IRR',
    'ISK', 'JPY', 'KGS', 'KRW', 'KWD', 'KZT', 'MDL', 'NOK', 'NZD', 'PLN',
    'QAR', 'RON', 'RSD', 'RUB', 'SEK', 'SGD', 'TJS', 'TMT', 'TRY', 'UAH',
    'USD', 'UZS', 'ZAR',
  ];
}

class CbbhProvider implements CurrencyProvider {
  @override
  String get id => 'cbbh';

  @override
  String get name => 'Centralna banka Bosne i Hercegovine';

  @override
  String get initials => 'CBBH';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBBH] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
      final response = await http.get(
        Uri.https(
          'cbbh.ba',
          '/CurrencyExchange/GetXml',
          {'date': dateStr},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[CBBH] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final items = document.findAllElements('CurrencyExchangeItem');
        if (items.isEmpty) {
          print('[CBBH] ERROR: No CurrencyExchangeItem elements found');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in items) {
          final codeElem = item.findElements('AlphaCode').firstOrNull;
          final unitsElem = item.findElements('Units').firstOrNull;
          final middleElem = item.findElements('Middle').firstOrNull;

          final code = codeElem?.innerText.trim();
          final unitsStr = unitsElem?.innerText.trim();
          final rateStr = middleElem?.innerText.trim();

          if (code == null || rateStr == null || rateStr.isEmpty) continue;

          final units = int.tryParse(unitsStr ?? '1') ?? 1;
          final rate = double.tryParse(rateStr);
          if (units == 0 || rate == null || rate == 0) continue;

          rawRates[code] = rate / units;
        }

        print('[CBBH] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CBBH] ERROR: rawRates is empty');
          return null;
        }

        // BAM itself
        rawRates['BAM'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBBH] Normalized rates count: ${normalized.length}');
        print('[CBBH] Normalized EUR: ${normalized['EUR']}');
        print('[CBBH] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBBH] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBBH] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBBH] ERROR: $e');
      print('[CBBH] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BAM', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HUF',
    'JPY', 'NOK', 'RSD', 'RUB', 'SEK', 'TRY', 'USD', 'XDR',
  ];
}

class CbbProvider implements CurrencyProvider {
  @override
  String get id => 'cbb';

  @override
  String get name => 'Central Bank of Bahrain';

  @override
  String get initials => 'CBB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('cbb.gov.bh', '/openapi/ExchangeRate'),
      ).timeout(const Duration(seconds: 15));

      print('[CBB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final items = jsonData['items'];
        if (items is! List) {
          print('[CBB] ERROR: items is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in items) {
          if (item is! Map) continue;
          final code = item['CurrCd'] as String?;
          final rateStr = item['BdCurr'] as String?;
          if (code == null || rateStr == null) continue;

          final rate = double.tryParse(rateStr.trim());
          if (rate == null || rate == 0) continue;

          rawRates[code] = rate;
        }

        print('[CBB] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CBB] ERROR: rawRates is empty');
          return null;
        }

        // BHD itself
        rawRates['BHD'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBB] Normalized rates count: ${normalized.length}');
        print('[CBB] Normalized EUR: ${normalized['EUR']}');
        print('[CBB] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBB] ERROR: $e');
      print('[CBB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BDT', 'BHD', 'CAD', 'CHF', 'CNY', 'EGP', 'EUR', 'GBP',
    'HKD', 'IDR', 'ILS', 'INR', 'JOD', 'JPY', 'KWD', 'LBP', 'LKR', 'MAD',
    'NOK', 'NPR', 'NZD', 'OMR', 'PHP', 'PKR', 'QAR', 'SAR', 'SGD', 'THB',
    'TND', 'TRY', 'USD',
  ];
}

class CbcTaiwanProvider implements CurrencyProvider {
  @override
  String get id => 'cbc_taiwan';

  @override
  String get name => 'Central Bank of Taiwan';

  @override
  String get initials => 'CBC';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBC_TW] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'cpx.cbc.gov.tw',
          '/API/DataAPI/Get',
          {'FileName': 'BP01D01'},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[CBC_TW] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final dataObj = jsonData['data'];
        if (dataObj is! Map) {
          print('[CBC_TW] ERROR: data is not a Map');
          return null;
        }

        final dataSets = dataObj['dataSets'];
        final structure = dataObj['structure'];
        if (dataSets is! List || structure is! Map) {
          print('[CBC_TW] ERROR: dataSets or structure missing');
          return null;
        }

        final table = structure['Table1'];
        if (table is! List) {
          print('[CBC_TW] ERROR: Table1 missing');
          return null;
        }

        if (dataSets.isEmpty) {
          print('[CBC_TW] ERROR: dataSets is empty');
          return null;
        }

        final lastRow = dataSets.last;
        if (lastRow is! List || lastRow.length < 2) {
          print('[CBC_TW] ERROR: lastRow invalid');
          return null;
        }

        // Labels to (currencyCode, isUsdPerCurrency)
        final labelMapping = <String, (String?, bool)>{
          '新台幣NTD/USD': ('TWD', false),
          '日圓JPY/USD': ('JPY', false),
          '英鎊USD/GBP': ('GBP', true),
          '港幣HKD/USD': ('HKD', false),
          '韓元KRW/USD': ('KRW', false),
          '加拿大幣CAD/USD': ('CAD', false),
          '新加坡元SGD/USD': ('SGD', false),
          '人民幣CNY/USD': ('CNY', false),
          '澳幣USD/AUD': ('AUD', true),
          '印尼盾IDR/USD': ('IDR', false),
          '泰銖THB/USD': ('THB', false),
          '馬來西亞幣MYR/USD': ('MYR', false),
          ' 菲律賓披索PHP/USD': ('PHP', false),
          '歐元USD/EUR': ('EUR', true),
          '馬克DEM/USD': (null, false),
          '法國法郎FRF/USD': (null, false),
          '荷蘭幣NLG/USD': (null, false),
          '越南盾VND/USD': ('VND', false),
        };

        final rawRates = <String, double>{'USD': 1.0};

        for (var i = 0; i < table.length; i++) {
          final labelEntry = table[i];
          if (labelEntry is! Map) continue;
          final label = labelEntry['data'] as String?;
          if (label == null) continue;

          final mapping = labelMapping[label];
          if (mapping == null) continue;

          final (code, isUsdPerCurrency) = mapping;
          if (code == null) continue;

          // dataSets row: [date, value1, value2, ...]
          final valueIndex = i + 1;
          if (valueIndex >= lastRow.length) continue;

          final valueStr = lastRow[valueIndex];
          if (valueStr == null || valueStr == '-') continue;

          final value = double.tryParse(valueStr.toString());
          if (value == null || value == 0) continue;

          if (isUsdPerCurrency) {
            rawRates[code] = value; // USD per currency
          } else {
            rawRates[code] = 1.0 / value; // USD per currency
          }
        }

        print('[CBC_TW] Parsed ${rawRates.length} raw rates');

        if (rawRates.length < 3) {
          print('[CBC_TW] ERROR: too few raw rates');
          return null;
        }

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBC_TW] Normalized rates count: ${normalized.length}');
        print('[CBC_TW] Normalized EUR: ${normalized['EUR']}');
        print('[CBC_TW] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBC_TW] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBC_TW] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBC_TW] ERROR: $e');
      print('[CBC_TW] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CNY', 'EUR', 'GBP', 'HKD', 'IDR', 'JPY', 'KRW', 'MYR',
    'PHP', 'SGD', 'THB', 'TWD', 'USD', 'VND',
  ];
}

class CbmProvider implements CurrencyProvider {
  @override
  String get id => 'cbm';

  @override
  String get name => 'Central Bank of Myanmar';

  @override
  String get initials => 'CBM';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBM] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('forex.cbm.gov.mm', '/api/latest'),
      ).timeout(const Duration(seconds: 15));

      print('[CBM] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesMap = jsonData['rates'];
        if (ratesMap is! Map) {
          print('[CBM] ERROR: rates is not a Map');
          return null;
        }

        final rawRates = <String, double>{};
        for (final entry in ratesMap.entries) {
          final code = entry.key as String?;
          final rateStr = entry.value;
          if (code == null || rateStr == null) continue;

          final rate = double.tryParse(rateStr.toString());
          if (rate == null || rate == 0) continue;

          rawRates[code] = rate;
        }

        print('[CBM] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[CBM] ERROR: rawRates is empty');
          return null;
        }

        // MMK itself
        rawRates['MMK'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBM] Normalized rates count: ${normalized.length}');
        print('[CBM] Normalized EUR: ${normalized['EUR']}');
        print('[CBM] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBM] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBM] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBM] ERROR: $e');
      print('[CBM] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BDT', 'BND', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EGP',
    'EUR', 'GBP', 'HKD', 'IDR', 'ILS', 'INR', 'JPY', 'KES', 'KHR', 'KRW',
    'KWD', 'LAK', 'LKR', 'MMK', 'MYR', 'NOK', 'NPR', 'NZD', 'PHP', 'PKR',
    'RSD', 'RUB', 'SAR', 'SEK', 'SGD', 'THB', 'USD', 'VND', 'ZAR',
  ];
}

class NrbProvider implements CurrencyProvider {
  @override
  String get id => 'nrb';

  @override
  String get name => 'Nepal Rastra Bank';

  @override
  String get initials => 'NRB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NRB] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http.get(
        Uri.https(
          'www.nrb.org.np',
          '/api/forex/v1/rates',
          {
            'page': '1',
            'per_page': '5',
            'from': dateStr,
            'to': dateStr,
          },
        ),
      ).timeout(const Duration(seconds: 15));

      print('[NRB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final dataObj = jsonData['data'];
        if (dataObj is! Map) {
          print('[NRB] ERROR: data is not a Map');
          return null;
        }

        final payload = dataObj['payload'];
        if (payload is! List || payload.isEmpty) {
          print('[NRB] ERROR: payload is empty or not a List');
          return null;
        }

        final dayData = payload.first;
        if (dayData is! Map) {
          print('[NRB] ERROR: first payload item is not a Map');
          return null;
        }

        final ratesList = dayData['rates'];
        if (ratesList is! List) {
          print('[NRB] ERROR: rates is not a List');
          return null;
        }

        final rawRates = <String, double>{};
        for (final item in ratesList) {
          if (item is! Map) continue;
          final currency = item['currency'];
          if (currency is! Map) continue;

          final code = currency['iso3'] as String?;
          final unit = currency['unit'];
          final buyStr = item['buy'];
          final sellStr = item['sell'];

          if (code == null || unit == null || buyStr == null || sellStr == null) {
            continue;
          }

          final buy = double.tryParse(buyStr.toString());
          final sell = double.tryParse(sellStr.toString());
          final unitVal = double.tryParse(unit.toString());

          if (buy == null || sell == null || unitVal == null || unitVal == 0) {
            continue;
          }

          // Middle rate per 1 unit of foreign currency
          rawRates[code] = ((buy + sell) / 2) / unitVal;
        }

        print('[NRB] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[NRB] ERROR: rawRates is empty');
          return null;
        }

        // NPR itself
        rawRates['NPR'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NRB] Normalized rates count: ${normalized.length}');
        print('[NRB] Normalized EUR: ${normalized['EUR']}');
        print('[NRB] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NRB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NRB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NRB] ERROR: $e');
      print('[NRB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BHD', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'HKD',
    'INR', 'JPY', 'KRW', 'KWD', 'MYR', 'NPR', 'OMR', 'QAR', 'SAR', 'SEK',
    'SGD', 'THB', 'USD',
  ];
}

class BcrpProvider implements CurrencyProvider {
  @override
  String get id => 'bcrp';

  @override
  String get name => 'Central Reserve Bank of Peru';

  @override
  String get initials => 'BCRP';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCRP] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'estadisticas.bcrp.gob.pe',
          '/estadisticas/series/api/PD04645PD-PD04646PD-PD04699XD-PD04698XD-PD04697XD/json',
        ),
      ).timeout(const Duration(seconds: 15));

      print('[BCRP] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final config = jsonData['config'];
        final periods = jsonData['periods'];
        if (config is! Map || periods is! List || periods.isEmpty) {
          print('[BCRP] ERROR: invalid response structure');
          return null;
        }

        // Find the latest period with all valid numeric values
        Map? validPeriod;
        for (var i = periods.length - 1; i >= 0; i--) {
          final period = periods[i] as Map?;
          if (period == null) continue;
          final vals = period['values'];
          if (vals is! List || vals.length < 5) continue;

          var allValid = true;
          for (final v in vals) {
            if (double.tryParse(v.toString()) == null ||
                double.tryParse(v.toString()) == 0) {
              allValid = false;
              break;
            }
          }
          if (allValid) {
            validPeriod = period;
            break;
          }
        }

        if (validPeriod == null) {
          print('[BCRP] ERROR: no valid period found');
          return null;
        }

        final values = validPeriod['values'];

        // Series order from API config:
        // values[0] = PEN per USD (buy)
        // values[1] = PEN per USD (sell)
        // values[2] = SDR per USD
        // values[3] = JPY per USD
        // values[4] = USD per EUR

        final penPerUsdBuy = double.parse(values[0].toString());
        final penPerUsdSell = double.parse(values[1].toString());
        final sdrPerUsd = double.parse(values[2].toString());
        final jpyPerUsd = double.parse(values[3].toString());
        final usdPerEur = double.parse(values[4].toString());

        // Use middle rate for USD
        final penPerUsd = (penPerUsdBuy + penPerUsdSell) / 2;

        final rawRates = <String, double>{
          'PEN': 1.0,
          'USD': penPerUsd,
          'EUR': penPerUsd * usdPerEur,
          'JPY': penPerUsd / jpyPerUsd,
          'XDR': penPerUsd / sdrPerUsd,
        };

        print('[BCRP] Parsed ${rawRates.length} raw rates');
        print('[BCRP] PEN/USD: $penPerUsd');
        print('[BCRP] PEN/EUR: ${rawRates['EUR']}');
        print('[BCRP] PEN/JPY: ${rawRates['JPY']}');
        print('[BCRP] PEN/XDR: ${rawRates['XDR']}');

        final normalized = _normalizeToEurBase(rawRates);
        print('[BCRP] Normalized rates count: ${normalized.length}');
        print('[BCRP] Normalized EUR: ${normalized['EUR']}');
        print('[BCRP] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[BCRP] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BCRP] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCRP] ERROR: $e');
      print('[BCRP] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'EUR', 'JPY', 'PEN', 'USD', 'XDR',
  ];
}

class CbcgProvider implements CurrencyProvider {
  @override
  String get id => 'cbcg';

  @override
  String get name => 'Central Bank of Montenegro';

  @override
  String get initials => 'CBCG';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBCG] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http.get(
        Uri.https(
          'www.cbcg.me',
          '/download.php',
          {'date': dateStr},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[CBCG] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final exchangeRates = <String, double>{'EUR': 1.0};
        final body = response.body;

        // Response uses <br /> as line separators
        final lines = body.split('<br />');
        for (var line in lines) {
          line = line.trim();
          if (line.isEmpty) continue;

          final parts = line.split(';');
          if (parts.length < 11) continue;

          final code = parts[4].trim();
          final rateStr = parts[9].trim();

          if (code.isEmpty || rateStr.isEmpty) continue;

          final rate = double.tryParse(rateStr);
          if (rate == null || rate == 0) continue;

          exchangeRates[code] = rate;
        }

        print('[CBCG] Parsed ${exchangeRates.length} rates');

        if (exchangeRates.length < 3) {
          print('[CBCG] ERROR: too few rates');
          return null;
        }

        print('[CBCG] EUR: ${exchangeRates['EUR']}');
        print('[CBCG] USD: ${exchangeRates['USD']}');
        return exchangeRates;
      }
      print('[CBCG] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBCG] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBCG] ERROR: $e');
      print('[CBCG] Stack: $st');
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

class BiIndonesiaProvider implements CurrencyProvider {
  @override
  String get id => 'bi_indonesia';

  @override
  String get name => 'Bank Indonesia';

  @override
  String get initials => 'BI';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BI_ID] Starting fetchRates()');
    try {
      // Try today and up to 7 previous days to find data
      http.Response? response;
      String? effectiveDate;
      for (var i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final tryResponse = await http.get(
          Uri.https(
            'www.bi.go.id',
            '/biwebservice/wskursbi.asmx/getSubKursLokal2',
            {'tgl': dateStr},
          ),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        ).timeout(const Duration(seconds: 15));

        if (tryResponse.statusCode == 200) {
          final doc = XmlDocument.parse(tryResponse.body);
          final tables = doc.findAllElements('Table').toList();
          // Schema-only responses have ~1 Table (the xs:element definition)
          if (tables.length > 1) {
            response = tryResponse;
            effectiveDate = dateStr;
            break;
          }
        }
      }

      print('[BI_ID] Effective date: $effectiveDate');

      if (response != null && response.statusCode == 200) {
        final rawRates = <String, double>{};
        final document = XmlDocument.parse(response.body);
        final allTables = document.findAllElements('Table').toList();
        print('[BI_ID] Found ${allTables.length} Table elements');

        for (final table in allTables) {
          final codeElem = table.findElements('mts_subkurslokal').firstOrNull;
          final unitElem = table.findElements('nil_subkurslokal').firstOrNull;
          final buyElem = table.findElements('beli_subkurslokal').firstOrNull;
          final sellElem = table.findElements('jual_subkurslokal').firstOrNull;

          if (codeElem == null ||
              unitElem == null ||
              buyElem == null ||
              sellElem == null) {
            continue;
          }

          final code = codeElem.innerText.trim();
          final unit = double.tryParse(unitElem.innerText);
          final buy = double.tryParse(buyElem.innerText);
          final sell = double.tryParse(sellElem.innerText);

          if (code.isEmpty ||
              unit == null ||
              unit == 0 ||
              buy == null ||
              sell == null) {
            continue;
          }

          // Middle rate per 1 unit of foreign currency in IDR
          rawRates[code] = ((buy + sell) / 2) / unit;
        }

        print('[BI_ID] Parsed ${rawRates.length} raw rates');

        if (rawRates.isEmpty) {
          print('[BI_ID] ERROR: rawRates is empty');
          return null;
        }

        // IDR itself
        rawRates['IDR'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BI_ID] Normalized rates count: ${normalized.length}');
        print('[BI_ID] Normalized EUR: ${normalized['EUR']}');
        print('[BI_ID] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[BI_ID] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BI_ID] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BI_ID] ERROR: $e');
      print('[BI_ID] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BND', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'HKD',
    'IDR', 'JPY', 'KRW', 'KWD', 'LAK', 'MYR', 'NOK', 'NZD', 'PGK', 'PHP',
    'SAR', 'SEK', 'SGD', 'THB', 'USD', 'VND',
  ];
}

class HnbProvider implements CurrencyProvider {
  @override
  String get id => 'hnb';

  @override
  String get name => 'Croatian National Bank';

  @override
  String get initials => 'HNB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[HNB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('api.hnb.hr', '/tecajn-eur/v3'),
      ).timeout(const Duration(seconds: 15));

      print('[HNB] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List) {
          print('[HNB] ERROR: response is not a List');
          return null;
        }

        final exchangeRates = <String, double>{'EUR': 1.0};

        for (final item in jsonData) {
          if (item is! Map) continue;
          final code = item['valuta'] as String?;
          final rateStr = item['srednji_tecaj'] as String?;
          if (code == null || rateStr == null) continue;

          // Croatian format uses comma as decimal separator
          final cleanRateStr = rateStr.replaceAll(',', '.');
          final rate = double.tryParse(cleanRateStr);
          if (rate == null || rate == 0) continue;

          exchangeRates[code] = rate;
        }

        print('[HNB] Parsed ${exchangeRates.length} rates');

        if (exchangeRates.length < 3) {
          print('[HNB] ERROR: too few rates');
          return null;
        }

        print('[HNB] EUR: ${exchangeRates['EUR']}');
        print('[HNB] USD: ${exchangeRates['USD']}');
        return exchangeRates;
      }
      print('[HNB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[HNB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[HNB] ERROR: $e');
      print('[HNB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BAM', 'CAD', 'CHF', 'CZK', 'DKK', 'EUR', 'GBP', 'HUF', 'JPY',
    'NOK', 'PLN', 'SEK', 'USD',
  ];
}

class NbsProvider implements CurrencyProvider {
  @override
  String get id => 'nbs';

  @override
  String get name => 'National Bank of Slovakia';

  @override
  String get initials => 'NBS';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBS] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('nbs.sk', '/export/en/exchange-rate/latest/xml'),
      ).timeout(const Duration(seconds: 15));

      print('[NBS] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final exchangeRates = <String, double>{'EUR': 1.0};
        final document = XmlDocument.parse(response.body);

        // Navigate Cube > Cube > Cube elements
        final envelopeCube = document.findAllElements('Cube').firstOrNull;
        if (envelopeCube == null) {
          print('[NBS] ERROR: No Cube element found');
          return null;
        }

        final dayCube = envelopeCube.findAllElements('Cube').firstOrNull;
        if (dayCube == null) {
          print('[NBS] ERROR: No day Cube element found');
          return null;
        }

        for (final cube in dayCube.findAllElements('Cube')) {
          final currency = cube.getAttribute('currency');
          final rateStr = cube.getAttribute('rate');
          if (currency == null || rateStr == null) continue;

          // Remove thousands separators (commas)
          final cleanRateStr = rateStr.replaceAll(',', '');
          final rate = double.tryParse(cleanRateStr);
          if (rate == null || rate == 0) continue;

          exchangeRates[currency] = rate;
        }

        print('[NBS] Parsed ${exchangeRates.length} rates');

        if (exchangeRates.length < 3) {
          print('[NBS] ERROR: too few rates');
          return null;
        }

        print('[NBS] EUR: ${exchangeRates['EUR']}');
        print('[NBS] USD: ${exchangeRates['USD']}');
        return exchangeRates;
      }
      print('[NBS] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBS] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBS] ERROR: $e');
      print('[NBS] Stack: $st');
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

class HkmaProvider implements CurrencyProvider {
  @override
  String get id => 'hkma';

  @override
  String get name => 'Hong Kong Monetary Authority';

  @override
  String get initials => 'HKMA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[HKMA] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'api.hkma.gov.hk',
          '/public/market-data-and-statistics/monthly-statistical-bulletin/er-ir/er-eeri-daily',
        ),
      ).timeout(const Duration(seconds: 15));

      print('[HKMA] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final result = jsonData['result'];
        if (result is! Map) {
          print('[HKMA] ERROR: result is not a Map');
          return null;
        }

        final records = result['records'];
        if (records is! List || records.isEmpty) {
          print('[HKMA] ERROR: records is empty or not a List');
          return null;
        }

        final latestRecord = records.first as Map?;
        if (latestRecord == null) {
          print('[HKMA] ERROR: first record is null');
          return null;
        }

        // Field name to ISO currency code mapping
        final fieldMapping = <String, String>{
          'usd': 'USD',
          'gbp': 'GBP',
          'jpy': 'JPY',
          'cad': 'CAD',
          'aud': 'AUD',
          'sgd': 'SGD',
          'twd': 'TWD',
          'chf': 'CHF',
          'cny': 'CNY',
          'krw': 'KRW',
          'thb': 'THB',
          'myr': 'MYR',
          'eur': 'EUR',
          'php': 'PHP',
          'inr': 'INR',
          'idr': 'IDR',
          'zar': 'ZAR',
          'special_drawing_rights': 'XDR',
        };

        final rawRates = <String, double>{'HKD': 1.0};

        for (final entry in fieldMapping.entries) {
          final value = latestRecord[entry.key];
          if (value == null) continue;
          final rate = double.tryParse(value.toString());
          if (rate == null || rate == 0) continue;
          rawRates[entry.value] = rate;
        }

        print('[HKMA] Parsed ${rawRates.length} raw rates');

        if (rawRates.length < 3) {
          print('[HKMA] ERROR: too few raw rates');
          return null;
        }

        final normalized = _normalizeToEurBase(rawRates);
        print('[HKMA] Normalized rates count: ${normalized.length}');
        print('[HKMA] Normalized EUR: ${normalized['EUR']}');
        print('[HKMA] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[HKMA] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[HKMA] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[HKMA] ERROR: $e');
      print('[HKMA] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD', 'IDR', 'INR', 'JPY',
    'KRW', 'MYR', 'PHP', 'SGD', 'THB', 'TWD', 'USD', 'XDR', 'ZAR',
  ];
}

class NbrmProvider implements CurrencyProvider {
  @override
  String get id => 'nbrm';

  @override
  String get name => 'National Bank of Republic Macedonia';

  @override
  String get initials => 'NBRM';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBRM] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 7));
      final formatter =
          '${startDate.day.toString().padLeft(2, '0')}.${startDate.month.toString().padLeft(2, '0')}.${startDate.year}';
      final endFormatter =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

      final response = await http.get(
        Uri.https(
          'www.nbrm.mk',
          '/KLServiceNOV/GetExchangeRate',
          {
            'StartDate': formatter,
            'EndDate': endFormatter,
            'format': 'json',
          },
        ),
      ).timeout(const Duration(seconds: 15));

      print('[NBRM] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List) {
          print('[NBRM] ERROR: response is not a List');
          return null;
        }

        // Group all entries by date
        final ratesByDate = <DateTime, Map<String, double>>{};

        for (final item in jsonData) {
          if (item is! Map) continue;
          final code = item['oznaka'] as String?;
          final rateStr = item['sreden'];
          final nominStr = item['nomin'];
          final datumStr = item['datum'] as String?;
          if (code == null || rateStr == null || nominStr == null) continue;

          final rate = double.tryParse(rateStr.toString());
          final nomin = double.tryParse(nominStr.toString());
          if (rate == null || nomin == null || nomin == 0) continue;

          DateTime? datum;
          if (datumStr != null) {
            try {
              datum = DateTime.parse(datumStr);
            } catch (_) {}
          }
          if (datum == null) continue;

          ratesByDate.putIfAbsent(datum, () => <String, double>{})[code] =
              rate / nomin;
        }

        if (ratesByDate.isEmpty) {
          print('[NBRM] ERROR: no valid entries');
          return null;
        }

        // Pick the latest date
        final latestDate = ratesByDate.keys.reduce((a, b) => a.isAfter(b) ? a : b);
        final rawRates = ratesByDate[latestDate]!;

        print('[NBRM] Parsed ${rawRates.length} raw rates for date $latestDate');

        if (rawRates.isEmpty) {
          print('[NBRM] ERROR: rawRates is empty');
          return null;
        }

        // MKD itself
        rawRates['MKD'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBRM] Normalized rates count: ${normalized.length}');
        print('[NBRM] Normalized EUR: ${normalized['EUR']}');
        print('[NBRM] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBRM] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBRM] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBRM] ERROR: $e');
      print('[NBRM] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HKD',
    'HUF', 'IDR', 'ILS', 'INR', 'JPY', 'KRW', 'MKD', 'MXN', 'MYR', 'NOK',
    'NZD', 'PHP', 'PLN', 'RON', 'RSD', 'RUB', 'SEK', 'SGD', 'THB', 'TRY',
    'USD', 'ZAR',
  ];
}

class CbnProvider implements CurrencyProvider {
  @override
  String get id => 'cbn';

  @override
  String get name => 'Central Bank of Nigeria';

  @override
  String get initials => 'CBN';

  /// Maps CBN currency names to ISO codes.
  static final _currencyNameToCode = <String, String>{
    'YUAN/RENMINBI': 'CNY',
    'DANISH KRONA': 'DKK',
    'EURO': 'EUR',
    'YEN': 'JPY',
    'RIYAL': 'SAR',
    'SOUTH AFRICAN RAND': 'ZAR',
    'SWISS FRANC': 'CHF',
    'POUNDS STERLING': 'GBP',
    'US DOLLAR': 'USD',
    'UAE DIRHAM': 'AED',
  };

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBN] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('www.cbn.gov.ng', '/api/GetAllExchangeRatesGRAPH'),
      ).timeout(const Duration(seconds: 20));

      print('[CBN] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData is! List) {
          print('[CBN] ERROR: response is not a List');
          return null;
        }

        // Group entries by date
        final ratesByDate = <DateTime, Map<String, double>>{};

        for (final item in jsonData) {
          if (item is! Map) continue;
          final currencyName = item['currency'] as String?;
          final centralRateStr = item['centralrate'] as String?;
          final dateStr = item['ratedate'] as String?;
          if (currencyName == null || centralRateStr == null || dateStr == null) continue;

          final code = _currencyNameToCode[currencyName.toUpperCase()];
          if (code == null) continue;

          final rate = double.tryParse(centralRateStr);
          if (rate == null || rate == 0) continue;

          final date = DateTime.tryParse(dateStr);
          if (date == null) continue;

          ratesByDate.putIfAbsent(date, () => <String, double>{})[code] = rate;
        }

        if (ratesByDate.isEmpty) {
          print('[CBN] ERROR: no valid entries');
          return null;
        }

        // Pick the latest date
        final latestDate = ratesByDate.keys.reduce((a, b) => a.isAfter(b) ? a : b);
        final rawRates = ratesByDate[latestDate]!;

        print('[CBN] Parsed ${rawRates.length} raw rates for date $latestDate');

        if (rawRates.isEmpty) {
          print('[CBN] ERROR: rawRates is empty');
          return null;
        }

        // NGN itself
        rawRates['NGN'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBN] Normalized rates count: ${normalized.length}');
        print('[CBN] Normalized EUR: ${normalized['EUR']}');
        print('[CBN] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[CBN] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBN] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBN] ERROR: $e');
      print('[CBN] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'JPY', 'NGN', 'SAR', 'USD',
    'ZAR',
  ];
}

class BankOfFinlandProvider implements CurrencyProvider {
  @override
  String get id => 'bank_of_finland';

  @override
  String get name => 'Bank of Finland';

  @override
  String get initials => 'BOF';

  /// Decodes UTF-16LE bytes to a Dart String.
  static String _decodeUtf16Le(List<int> bytes) {
    var start = 0;
    // Skip BOM if present
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      start = 2;
    }
    final codeUnits = <int>[];
    for (var i = start; i < bytes.length - 1; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BOF] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'api.boffsaopendata.fi',
          '/referencerates/api/ExchangeRate',
        ),
      ).timeout(const Duration(seconds: 15));

      print('[BOF] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        // The API returns UTF-16LE without a proper charset in Content-Type.
        // Detect by checking if the first byte is '[' (0x5b) followed by 0x00.
        final bodyBytes = response.bodyBytes;
        final bodyText = (bodyBytes.length >= 2 &&
                bodyBytes[0] == 0x5B &&
                bodyBytes[1] == 0x00)
            ? _decodeUtf16Le(bodyBytes)
            : response.body;

        final jsonData = jsonDecode(bodyText);
        if (jsonData is! List) {
          print('[BOF] ERROR: response is not a List');
          return null;
        }

        final exchangeRates = <String, double>{'EUR': 1.0};

        for (final item in jsonData) {
          if (item is! Map) continue;

          final currency = item['Currency'] as String?;
          final denom = item['CurrencyDenom'] as String?;
          final ecbPublished = item['ECBPublished'] as String?;
          final ratesList = item['ExchangeRates'];

          if (currency == null ||
              denom == null ||
              ecbPublished == null ||
              ratesList == null) {
            continue;
          }

          // Only use EUR-denominated ECB rates
          if (denom != 'EUR' || ecbPublished != 'true') continue;

          if (ratesList is! List || ratesList.isEmpty) continue;

          // Find the latest observation
          double? latestValue;
          DateTime? latestDate;
          for (final rateItem in ratesList) {
            if (rateItem is! Map) continue;
            final dateStr = rateItem['ObservationDate'] as String?;
            final valueStr = rateItem['Value'] as String?;
            if (dateStr == null || valueStr == null) continue;

            final date = DateTime.tryParse(dateStr);
            final value = double.tryParse(valueStr);
            if (date == null || value == null || value == 0) continue;

            if (latestDate == null || date.isAfter(latestDate)) {
              latestDate = date;
              latestValue = value;
            }
          }

          if (latestValue != null) {
            exchangeRates[currency] = latestValue;
          }
        }

        print('[BOF] Parsed ${exchangeRates.length} rates');

        if (exchangeRates.length < 5) {
          print('[BOF] ERROR: too few rates');
          return null;
        }

        print('[BOF] EUR: ${exchangeRates['EUR']}');
        print('[BOF] USD: ${exchangeRates['USD']}');
        return exchangeRates;
      }
      print('[BOF] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BOF] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOF] ERROR: $e');
      print('[BOF] Stack: $st');
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

class BpstatProvider implements CurrencyProvider {
  @override
  String get id => 'bpstat';

  @override
  String get name => 'Banco de Portugal';

  @override
  String get initials => 'BP';

  /// Daily EUR-based exchange rate series IDs from BPstat (domain 29).
  /// Counterparty currency dimension (12) with EUR reference currency (13).
  static const _seriesIds = <String, int>{
    'AUD': 12531935,
    'CAD': 12531936,
    'CVE': 12531937,
    'CNY': 12531938,
    'CZK': 12531941,
    'DKK': 12531942,
    'HKD': 12531945,
    'HUF': 12531946,
    'ISK': 12531947,
    'INR': 12531948,
    'IDR': 12531949,
    'ILS': 12531950,
    'JPY': 12531951,
    'KRW': 12531952,
    'MOP': 12531955,
    'MYR': 12531956,
    'MXN': 12531958,
    'NZD': 12531959,
    'NOK': 12531960,
    'PHP': 12531961,
    'RUB': 12531962,
    'SGD': 12531963,
    'ZAR': 12531966,
    'SEK': 12531967,
    'CHF': 12531968,
    'THB': 12531969,
    'GBP': 12531970,
    'USD': 12531971,
    'BGN': 12531972,
    'PLN': 12531973,
    'TRY': 12531974,
    'RON': 12531975,
    'BRL': 12531976,
  };

  /// BPstat limits dataset queries to ~10 series per request.
  static const _batchSize = 10;

  static final _codeInParens = RegExp(r'\(([A-Z]{3})\)');

  Future<Map<String, double>?> _fetchBatch(List<int> ids) async {
    final idParam = ids.join(',');
    print('[BPSTAT] Fetching batch: $idParam');
    final response = await http.get(
      Uri.https(
        'bpstat.bportugal.pt',
        '/data/v1/domains/29/datasets/23e0cdd56bddb4ad3016a9c3ad63a539/',
        {'lang': 'EN', 'series_ids': idParam},
      ),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      print('[BPSTAT] Batch failed: ${response.statusCode}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final size = (data['size'] as List<dynamic>).cast<int>();
    final dimensions = (data['id'] as List<dynamic>).cast<String>();
    final values = data['value'] as List<dynamic>;

    // Find currency dimension index
    final currencyDimIdx = dimensions.indexOf('12');
    final dateDimIdx = dimensions.indexOf('reference_date');
    if (currencyDimIdx == -1 || dateDimIdx == -1) {
      print('[BPSTAT] ERROR: missing expected dimensions');
      return null;
    }

    // Number of dates (last dimension varies fastest)
    final nDates = size[dateDimIdx];

    // Stride for each dimension
    var stride = 1;
    for (var i = dimensions.length - 1; i > currencyDimIdx; i--) {
      stride *= size[i];
    }

    // Build category ID -> currency code mapping from series metadata.
    // Dataset dimension labels don't include codes, but series labels do.
    final catToCode = <String, String>{};
    final seriesList = data['extension']['series'] as List<dynamic>;
    for (final s in seriesList) {
      final series = s as Map<String, dynamic>;
      final label = series['label'] as String;
      final match = _codeInParens.firstMatch(label);
      if (match == null) continue;
      final code = match.group(1)!;
      final dimCats = series['dimension_category'] as List<dynamic>;
      for (final dc in dimCats) {
        final d = dc as Map<String, dynamic>;
        if (d['dimension_id'] == 12) {
          catToCode[d['category_id'].toString()] = code;
          break;
        }
      }
    }

    final dimData = data['dimension'] as Map<String, dynamic>;
    final currencyDim = dimData['12'] as Map<String, dynamic>;
    final currencyCat = currencyDim['category'] as Map<String, dynamic>;
    final currencyIndices =
        (currencyCat['index'] as List<dynamic>).cast<String>();

    final rates = <String, double>{};
    for (var c = 0; c < currencyIndices.length; c++) {
      final code = catToCode[currencyIndices[c]];
      if (code == null) continue;

      // Find the most recent non-null value for this currency
      double? latestValue;
      for (var d = nDates - 1; d >= 0; d--) {
        final valIdx = c * stride + d;
        if (valIdx >= values.length) continue;
        final val = values[valIdx];
        if (val != null && val is num) {
          latestValue = val.toDouble();
          break;
        }
      }
      if (latestValue != null && latestValue > 0) {
        rates[code] = latestValue;
      }
    }
    return rates;
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BPSTAT] Starting fetchRates()');
    try {
      final ids = _seriesIds.values.toList();
      final batches = <List<int>>[];
      for (var i = 0; i < ids.length; i += _batchSize) {
        batches.add(ids.sublist(i, i + _batchSize > ids.length ? ids.length : i + _batchSize));
      }

      final results = await Future.wait(
        batches.map(_fetchBatch),
      );

      final exchangeRates = <String, double>{'EUR': 1.0};
      for (final batchRates in results) {
        if (batchRates != null) {
          exchangeRates.addAll(batchRates);
        }
      }

      print('[BPSTAT] Parsed ${exchangeRates.length} rates');
      if (exchangeRates.length < 5) {
        print('[BPSTAT] ERROR: too few rates');
        return null;
      }

      print('[BPSTAT] EUR: ${exchangeRates['EUR']}');
      print('[BPSTAT] USD: ${exchangeRates['USD']}');
      return exchangeRates;
    } on TimeoutException catch (e) {
      print('[BPSTAT] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BPSTAT] ERROR: $e');
      print('[BPSTAT] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BGN', 'BRL', 'CAD', 'CHF', 'CNY', 'CVE', 'CZK', 'DKK', 'EUR',
    'GBP', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'ISK', 'JPY', 'KRW', 'MOP',
    'MXN', 'MYR', 'NOK', 'NZD', 'PHP', 'PLN', 'RON', 'RUB', 'SEK', 'SGD',
    'THB', 'TRY', 'USD', 'ZAR',
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
  BnmProvider(),
  CnbProvider(),
  MnbProvider(),
  TcmbProvider(),
  BccProvider(),
  BoiProvider(),
  NbrkProvider(),
  CbuProvider(),
  NbuProvider(),
  CbaProvider(),
  NbgProvider(),
  CbbhProvider(),
  CbcTaiwanProvider(),
  CbbProvider(),
  NbrmProvider(),
  HkmaProvider(),
  NbsProvider(),
  CbmProvider(),
  NrbProvider(),
  HnbProvider(),
  BcrpProvider(),
  BiIndonesiaProvider(),
  CbcgProvider(),
  BpstatProvider(),
  CbnProvider(),
  BankOfFinlandProvider(),
];

CurrencyProvider getCurrencyProviderById(String id) {
  return currencyProviders.firstWhere(
    (p) => p.id == id,
    orElse: () => currencyProviders.first,
  );
}
