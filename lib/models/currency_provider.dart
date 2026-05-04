import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
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
          host == 'static.nbp.pl' ||
          host == 'www.bcv.org.ve' ||
          host == 'www.bcv.cv' ||
          host == 'www.cbs.sc';
    };
  return IOClient(httpClient);
}

String _extractPdfText(List<int> bytes) {
  final buffer = StringBuffer();
  final pdfStr = latin1.decode(bytes);

  var startIdx = 0;
  while (true) {
    final streamPos = pdfStr.indexOf('stream\n', startIdx);
    if (streamPos == -1) {
      // Try \r\n variant
      final streamPos2 = pdfStr.indexOf('stream\r\n', startIdx);
      if (streamPos2 == -1) break;
      final dataStart = streamPos2 + 8;
      final endPos = pdfStr.indexOf('\r\nendstream', dataStart);
      if (endPos == -1) break;
      _tryExtractPdfStream(bytes, dataStart, endPos, buffer);
      startIdx = endPos + 12;
    } else {
      final dataStart = streamPos + 7;
      final endPos = pdfStr.indexOf('\nendstream', dataStart);
      if (endPos == -1) break;
      _tryExtractPdfStream(bytes, dataStart, endPos, buffer);
      startIdx = endPos + 11;
    }
  }

  return buffer.toString();
}

void _tryExtractPdfStream(
  List<int> bytes,
  int dataStart,
  int dataEnd,
  StringBuffer buffer,
) {
  try {
    final streamBytes = bytes.sublist(dataStart, dataEnd);
    final decompressed = const ZLibDecoder().decodeBytes(streamBytes);
    final decodedStr = latin1.decode(decompressed);

    // Extract text from TJ array operators: [(s1)(s2)] TJ
    final tjPattern = RegExp(r'\[([^\]]*)\]\s*TJ', dotAll: true);
    for (final match in tjPattern.allMatches(decodedStr)) {
      final arr = match.group(1)!;
      final strPattern = RegExp(r'\(([^)]*)\)');
      final pieces = <String>[];
      for (final strMatch in strPattern.allMatches(arr)) {
        pieces.add(strMatch.group(1)!);
      }
      final combined = pieces.join();
      if (combined.trim().isNotEmpty) {
        buffer.write(combined);
        buffer.write(' ');
      }
    }
  } catch (_) {
    // Not a zlib stream or parsing error – ignore
  }
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

class BermudaCustomsProvider implements CurrencyProvider {
  @override
  String get id => 'bermuda_customs';

  @override
  String get name => 'Bermuda Customs';

  @override
  String get initials => 'BMD';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.gov.bm/weekly-exchange-rates-importers'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return parseBermudaCustomsHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBermudaCustomsHtml(String html) {
    // Find the first exchange-rate table (most recent month is first).
    final tableRegExp = RegExp(
      r'<table[^>]*>(.*?)</table>',
      caseSensitive: false,
      dotAll: true,
    );

    String? tableHtml;
    for (final match in tableRegExp.allMatches(html)) {
      final candidate = match.group(1)!;
      if (candidate.contains('U.S. Dollar')) {
        tableHtml = candidate;
        break;
      }
    }
    if (tableHtml == null) return null;

    final rawRates = <String, double>{};

    // Each row: Currency name (ISO) | first week rate | ...
    final rowRegExp = RegExp(
      r'<tr>\s*<td>([^<]+)</td>\s*<td>([0-9.]+)</td>',
      caseSensitive: false,
    );

    for (final match in rowRegExp.allMatches(tableHtml)) {
      final cellText = match.group(1)!.trim();
      final rate = double.tryParse(match.group(2)!);
      if (rate == null || rate <= 0) continue;

      final isoMatches = RegExp(r'([A-Z]{3})').allMatches(cellText);
      if (isoMatches.isEmpty) continue;
      final currency = isoMatches.last.group(1)!;

      rawRates[currency] = rate;
    }

    if (!rawRates.containsKey('EUR')) return null;

    // Rates are quoted as BMD per unit of foreign currency.
    rawRates['BMD'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BMD', 'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'HKD', 'JMD', 'JPY',
    'NOK', 'NZD', 'SEK', 'SGD', 'USD',
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

class BccCongoProvider implements CurrencyProvider {
  @override
  String get id => 'bcc_congo';

  @override
  String get name => 'Banque Centrale du Congo';

  @override
  String get initials => 'BCC';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://www.bcc.cd/operations-et-marches/domaine-operationnel/operations-de-change/cours-de-change',
        ),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return parseBccCongoHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBccCongoHtml(String html) {
    // Remove HTML comments to avoid matching commented-out cells
    final commentRegExp = RegExp(r'<!--.*?-->', dotAll: true);
    final cleanHtml = html.replaceAll(commentRegExp, '');

    // Find the first exchange-rate table
    final tableRegExp = RegExp(
      r'<table[^>]*class="table"[^>]*>(.*?)<\/table>',
      caseSensitive: false,
      dotAll: true,
    );

    String? tableHtml;
    for (final match in tableRegExp.allMatches(cleanHtml)) {
      final candidate = match.group(1)!;
      if (candidate.contains('<th>Code</th>')) {
        tableHtml = candidate;
        break;
      }
    }
    if (tableHtml == null) return null;

    final rawRates = <String, double>{};

    final rowRegExp = RegExp(
      r'<tr[^>]*>(.*?)<\/tr>',
      caseSensitive: false,
      dotAll: true,
    );

    final cellRegExp = RegExp(
      r'<td[^>]*>(.*?)<\/td>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final rowMatch in rowRegExp.allMatches(tableHtml)) {
      final row = rowMatch.group(1)!;
      final cells = cellRegExp.allMatches(row).map((m) {
        var text = m.group(1)!.trim();
        text = text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        return text;
      }).toList();

      if (cells.length < 3) continue;

      final code = cells[0];
      final rateStr = cells[2];

      if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) continue;

      // French number format: spaces as thousand separators, comma as decimal
      final normalizedRateStr = rateStr.replaceAll(' ', '').replaceAll(',', '.');
      final rate = double.tryParse(normalizedRateStr);
      if (rate == null || rate <= 0) continue;

      rawRates[code] = rate;
    }

    if (!rawRates.containsKey('EUR')) return null;

    // Rates are quoted as CDF per unit of foreign currency
    rawRates['CDF'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AOA', 'AUD', 'BIF', 'CAD', 'CHF', 'CNY', 'CDF', 'EUR', 'GBP', 'JPY',
    'RWF', 'TZS', 'UGX', 'USD', 'XAF', 'XDR', 'ZAR', 'ZMW',
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

class CbarProvider implements CurrencyProvider {
  @override
  String get id => 'cbar';

  @override
  String get name => 'Central Bank of Azerbaijan';

  @override
  String get initials => 'CBAR';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBAR] Starting fetchRates()');
    try {
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

        final response = await http.get(
          Uri.http('www.cbar.az', '/currencies/$dateStr.xml'),
        ).timeout(const Duration(seconds: 30));

        print('[CBAR] Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final rawRates = parseCbarXml(response.body);
          if (rawRates == null || rawRates.isEmpty) {
            print('[CBAR] ERROR: parseCbarXml returned null or empty');
            continue;
          }

          // AZN itself
          rawRates['AZN'] = 1.0;

          final normalized = _normalizeToEurBase(rawRates);
          print('[CBAR] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      print('[CBAR] ERROR: statusCode != 200 after 7 days');
    } on TimeoutException catch (e) {
      print('[CBAR] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBAR] ERROR: $e');
      print('[CBAR] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseCbarXml(String xml) {
    try {
      final document = XmlDocument.parse(xml);
      final rawRates = <String, double>{};

      // Find the foreign-currencies ValType
      for (final valType in document.findAllElements('ValType')) {
        final typeAttr = valType.getAttribute('Type');
        if (typeAttr == null || !typeAttr.toLowerCase().contains('xarici')) {
          continue;
        }

        for (final valute in valType.findElements('Valute')) {
          final code = valute.getAttribute('Code');
          final nominalStr = valute.findElements('Nominal').firstOrNull?.innerText;
          final valueStr = valute.findElements('Value').firstOrNull?.innerText;

          if (code == null || valueStr == null) continue;

          // Skip precious metals (sometimes mixed in)
          if (code == 'XAU' || code == 'XAG' || code == 'XPT' || code == 'XPD') {
            continue;
          }

          // Parse nominal (may contain text like "100" or "1 t.u.")
          final nominalClean = nominalStr?.replaceAll(RegExp(r'[^0-9]'), '');
          final nominal = int.tryParse(nominalClean ?? '1') ?? 1;
          if (nominal == 0) continue;

          final value = double.tryParse(valueStr);
          if (value == null || value == 0) continue;

          // Rate is AZN per <nominal> units of foreign currency
          rawRates[code] = value / nominal;
        }
      }

      if (rawRates.isEmpty) return null;
      return rawRates;
    } catch (e) {
      print('[CBAR] ERROR parsing XML: $e');
      return null;
    }
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'AZN', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EUR',
    'GBP', 'GEL', 'HKD', 'HUF', 'ILS', 'INR', 'JPY', 'KGS', 'KRW', 'KWD',
    'KZT', 'MDL', 'NOK', 'NZD', 'PKR', 'PLN', 'QAR', 'RON', 'RUB', 'RSD',
    'SEK', 'SGD', 'SAR', 'SDR', 'TRY', 'TMT', 'UAH', 'USD', 'UZS',
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

class BcpProvider implements CurrencyProvider {
  @override
  String get id => 'bcp';

  @override
  String get name => 'Banco Central del Paraguay';

  @override
  String get initials => 'BCP';

  static final _nameToIso = <String, String>{
    'DÓLAR ESTADOUNIDENSE': 'USD',
    'YEN JAPONÉS': 'JPY',
    'LIBRA ESTERLINA': 'GBP',
    'FRANCO SUIZO': 'CHF',
    'CORONA SUECA': 'SEK',
    'CORONA DANESA': 'DKK',
    'CORONA NORUEGA': 'NOK',
    'REAL BRASILEÑO': 'BRL',
    'PESO ARGENTINO': 'ARS',
    'DÓLAR CANADIENSE': 'CAD',
    'RAND SUDAFRICANO': 'ZAR',
    'DERECHOS ESPECIALES DE GIRO': 'XDR',
    'ONZA DE ORO': 'XAU',
    'PESO CHILENO': 'CLP',
    'EURO': 'EUR',
    'PESO URUGUAYO': 'UYU',
    'DÓLAR AUSTRALIANO': 'AUD',
    'YUAN RENMINBI DE CHINA': 'CNY',
    'DÓLAR DE SINGAPUR': 'SGD',
    'BOLIVIANO': 'BOB',
    'SOL PERUANO': 'PEN',
    'DÓLAR NEOZELANDÉS': 'NZD',
    'PESO MEXICANO': 'MXN',
    'PESO COLOMBIANO': 'COP',
    'DÓLAR TAIWANÉS': 'TWD',
    'DIRHAM DE LOS EMIRATOS ÁRABES UNIDOS': 'AED',
  };

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCP] Starting fetchRates()');
    try {
      const url =
          'https://www.bcp.gov.py/webapps/web/cotizacion/monedas/pdf';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 &&
          response.bodyBytes.length > 4 &&
          String.fromCharCodes(response.bodyBytes.sublist(0, 4)) == '%PDF') {
        print('[BCP] Got PDF');
        final text = _extractPdfText(response.bodyBytes);
        final rawRates = parseBcpPdf(text);
        if (rawRates == null || rawRates.isEmpty) {
          print('[BCP] ERROR: parseBcpPdf returned null or empty');
          return null;
        }

        // PYG itself
        rawRates['PYG'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BCP] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BCP] ERROR: statusCode != 200 or not a PDF');
    } on TimeoutException catch (e) {
      print('[BCP] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCP] ERROR: $e');
      print('[BCP] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseBcpPdf(String text) {
    final rawRates = <String, double>{};

    // For each currency name, find its position in the text and then
    // locate the next two numeric tokens after it.
    for (final entry in _nameToIso.entries) {
      final name = entry.key;
      final iso = entry.value;
      if (iso == 'XAU') continue; // skip gold

      final idx = text.toUpperCase().indexOf(name.toUpperCase());
      if (idx == -1) continue;

      // Search forward from the end of the currency name for numbers
      final tail = text.substring(idx + name.length);
      final numberRegex = RegExp(r'[0-9.,]+');
      final numbers = numberRegex.allMatches(tail).toList();
      if (numbers.length < 2) continue;

      // The first two numbers after the currency name are rate2 and rate3
      final rate3Str = numbers[1].group(0)!;
      // Convert European number format (1.234,56 → 1234.56)
      final rate3 = double.tryParse(
        rate3Str.replaceAll('.', '').replaceAll(',', '.'),
      );
      if (rate3 == null || rate3 == 0) continue;

      rawRates[iso] = rate3;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'ARS', 'AUD', 'BOB', 'BRL', 'CAD', 'CHF', 'CLP', 'CNY', 'COP',
    'DKK', 'EUR', 'GBP', 'JPY', 'MXN', 'NOK', 'NZD', 'PEN', 'PYG', 'SEK',
    'SGD', 'TWD', 'USD', 'UYU', 'XDR', 'ZAR',
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

class BankNegaraMalaysiaProvider implements CurrencyProvider {
  @override
  String get id => 'bank_negara_malaysia';

  @override
  String get name => 'Bank Negara Malaysia';

  @override
  String get initials => 'BNM';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BNM_MY] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('api.bnm.gov.my', '/public/exchange-rate'),
        headers: {'accept': 'application/vnd.BNM.API.v1+json'},
      ).timeout(const Duration(seconds: 15));

      print('[BNM_MY] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final dataList = jsonData['data'];
        if (dataList is! List) {
          print('[BNM_MY] ERROR: data is not a List');
          return null;
        }

        final rawRates = <String, double>{};

        for (final item in dataList) {
          if (item is! Map) continue;

          var currencyCode = item['currency_code'] as String?;
          final unit = item['unit'] as num? ?? 1;
          final rateObj = item['rate'];

          if (currencyCode == null || rateObj is! Map) continue;

          final middleRate = rateObj['middle_rate'] as num?;
          if (middleRate == null || middleRate == 0 || unit == 0) continue;

          // Map SDR to XDR
          if (currencyCode == 'SDR') currencyCode = 'XDR';

          // Rate is MYR per <unit> of foreign currency
          rawRates[currencyCode] = middleRate.toDouble() / unit.toDouble();
        }

        print('[BNM_MY] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['MYR'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BNM_MY] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BNM_MY] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BNM_MY] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BNM_MY] ERROR: $e');
      print('[BNM_MY] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BND', 'CAD', 'CHF', 'CNY', 'EGP', 'EUR', 'GBP', 'HKD',
    'IDR', 'INR', 'JPY', 'KHR', 'KRW', 'MMK', 'MYR', 'NPR', 'NZD', 'PHP',
    'PKR', 'SAR', 'SGD', 'THB', 'TWD', 'USD', 'VND', 'XDR',
  ];
}
class BankOfLatviaProvider implements CurrencyProvider {
  @override
  String get id => 'bank_of_latvia';

  @override
  String get name => 'Bank of Latvia';

  @override
  String get initials => 'LVL';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BankOfLatvia] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('www.bank.lv', '/vk/ecb.xml'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/xml,text/xml,*/*',
        },
      ).timeout(const Duration(seconds: 15));

      print('[BankOfLatvia] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final rawRates = <String, double>{};

        final currencies = document.findAllElements('Currency');
        for (final currency in currencies) {
          final idElement = currency.getElement('ID');
          final rateElement = currency.getElement('Rate');

          if (idElement == null || rateElement == null) continue;

          final isoCode = idElement.innerText.trim().toUpperCase();
          final rateStr = rateElement.innerText.trim();
          if (isoCode.isEmpty || rateStr.isEmpty) continue;

          final rate = double.tryParse(rateStr);
          if (rate == null || rate == 0) continue;

          rawRates[isoCode] = rate;
        }

        print('[BankOfLatvia] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['EUR'] = 1.0;

        print('[BankOfLatvia] Returning ${rawRates.length} rates (EUR-based)');
        return rawRates;
      }
      print('[BankOfLatvia] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BankOfLatvia] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BankOfLatvia] ERROR: $e');
      print('[BankOfLatvia] Stack: $st');
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
class BankOfLithuaniaProvider implements CurrencyProvider {
  @override
  String get id => 'bank_of_lithuania';

  @override
  String get name => 'Bank of Lithuania';

  @override
  String get initials => 'LB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[LB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'lb.lt',
          '/webservices/fxrates/fxrates.asmx/getCurrentFxRates',
          {'tp': 'eu'},
        ),
      ).timeout(const Duration(seconds: 15));

      print('[LB] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final exchangeRates = <String, double>{};

        for (final fxRate in document.findAllElements('FxRate')) {
          final ccyAmtList = fxRate.findElements('CcyAmt').toList();
          if (ccyAmtList.length < 2) continue;

          final targetCcy = ccyAmtList[1].findElements('Ccy').firstOrNull?.innerText;
          final targetAmt = ccyAmtList[1].findElements('Amt').firstOrNull?.innerText;

          if (targetCcy == null || targetAmt == null) continue;

          final rate = double.tryParse(targetAmt);
          if (rate == null || rate == 0) continue;

          exchangeRates[targetCcy] = rate;
        }

        print('[LB] Parsed ${exchangeRates.length} rates');
        if (exchangeRates.isEmpty) return null;

        exchangeRates['EUR'] = 1.0;
        return exchangeRates;
      }
      print('[LB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[LB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[LB] ERROR: $e');
      print('[LB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'ALL', 'AMD', 'ARS', 'AUD', 'AZN', 'BAM', 'BDT', 'BHD',
    'BOB', 'BRL', 'BYN', 'CAD', 'CHF', 'CLP', 'CNY', 'COP', 'CZK', 'DKK',
    'DZD', 'EGP', 'ETB', 'EUR', 'GBP', 'GEL', 'GNF', 'HKD', 'HUF', 'IDR',
    'ILS', 'INR', 'IQD', 'IRR', 'ISK', 'JOD', 'JPY', 'KES', 'KGS', 'KRW',
    'KWD', 'KZT', 'LBP', 'LKR', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MNT',
    'MXN', 'MYR', 'MZN', 'NOK', 'NZD', 'PAB', 'PEN', 'PHP', 'PKR', 'PLN',
    'QAR', 'RON', 'RSD', 'RUB', 'SAR', 'SEK', 'SGD', 'SYP', 'THB', 'TJS',
    'TMT', 'TND', 'TRY', 'TWD', 'TZS', 'UAH', 'USD', 'UYU', 'UZS', 'VES',
    'VND', 'XAF', 'XOF', 'YER', 'ZAR',
  ];
}
class BcnProvider implements CurrencyProvider {
  @override
  String get id => 'bcn';

  @override
  String get name => 'Banco Central de Nicaragua';

  @override
  String get initials => 'BCN';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCN] Starting fetchRates()');
    try {
      // 1. Fetch EUR/USD from ECB (lightweight single-series query)
      final ecbResponse = await http.get(
        Uri.https(
          'data-api.ecb.europa.eu',
          'service/data/EXR/D.USD.EUR.SP00.A',
          {'lastNObservations': '1', 'detail': 'dataonly', 'format': 'csvdata'},
        ),
      ).timeout(const Duration(seconds: 15));

      double? eurUsdRate;
      if (ecbResponse.statusCode == 200) {
        final rows = const LineSplitter().convert(ecbResponse.body);
        for (var row in rows) {
          if (row.trim().isEmpty) continue;
          final parts = row.split(',');
          // CSV header contains OBS_VALUE; find the value in the last data row
          if (parts.length >= 2) {
            final value = double.tryParse(parts.last);
            if (value != null && value > 0) {
              eurUsdRate = value;
              break;
            }
          }
        }
      }

      if (eurUsdRate == null) {
        print('[BCN] ERROR: Could not fetch EUR/USD from ECB');
        return null;
      }
      print('[BCN] EUR/USD from ECB: $eurUsdRate');

      // 2. Fetch BCN PDF for USD/NIO
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final url =
            'https://www.bcn.gob.ni/IRR/tipo_cambio_mensual/tipoc_pdf.php?'
            'Fecha_inicial=$dateStr&Fecha_final=$dateStr';

        print('[BCN] Trying $url');
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 &&
            response.bodyBytes.length > 4 &&
            String.fromCharCodes(response.bodyBytes.sublist(0, 4)) == '%PDF') {
          print('[BCN] Got PDF for $dateStr');
          final text = _extractPdfText(response.bodyBytes);
          final usdNioRate = parseBcnPdf(text);
          print('[BCN] Parsed USD/NIO: $usdNioRate');

          if (usdNioRate == null || usdNioRate == 0) {
            print('[BCN] ERROR: Could not parse USD/NIO from PDF');
            continue;
          }

          // Compute EUR/NIO = EUR/USD * USD/NIO
          final eurNioRate = eurUsdRate * usdNioRate;
          final rates = <String, double>{
            'EUR': 1.0,
            'USD': eurUsdRate,
            'NIO': eurNioRate,
          };
          print('[BCN] Returning ${rates.length} rates');
          return rates;
        }
      }
      print('[BCN] No valid PDF found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[BCN] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCN] ERROR: $e');
      print('[BCN] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static double? parseBcnPdf(String text) {
    // Look for lines like "28-Abril-2026 36.6243"
    final lineRegex = RegExp(
      r'^\d{1,2}-[A-Za-z]+-\d{4}\s+([0-9]+\.[0-9]+)',
      multiLine: true,
    );
    final match = lineRegex.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  @override
  List<String> get supportedCurrencies => [
    'EUR', 'USD', 'NIO',
  ];
}

class BcvVenezuelaProvider implements CurrencyProvider {
  @override
  String get id => 'bcv_venezuela';

  @override
  String get name => 'Banco Central de Venezuela';

  @override
  String get initials => 'BCV';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final client = _createPermissiveClient();
      final response = await client
          .get(Uri.parse('https://www.bcv.org.ve/'))
          .timeout(const Duration(seconds: 15));
      client.close();

      print('[BCV-VE] Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('[BCV-VE] ERROR: GET failed with ${response.statusCode}');
        return null;
      }

      final result = parseBcvVenezuelaHtml(response.body);
      print('[BCV-VE] Parsed result: ${result != null ? '${result.length} rates' : 'null'}');
      return result;
    } on TimeoutException catch (e) {
      print('[BCV-VE] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCV-VE] ERROR: $e');
      print('[BCV-VE] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseBcvVenezuelaHtml(String html) {
    final rawRates = <String, double>{};

    // The BCV homepage shows reference rates in a sidebar widget.
    // Each currency is in a <div id="euro|dolar|yuan|lira|rublo"> block
    // with the ISO code in a <span> and the rate in a <strong>.
    final regex = RegExp(
      r'<div\s+id="(euro|dolar|yuan|lira|rublo)"[^>]*>.*?<span>\s*([A-Z]{3})\s*</span>.*?<strong>\s*([0-9.,]+)\s*</strong>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in regex.allMatches(html)) {
      final iso = match.group(2)!.toUpperCase();
      final rateStr = match.group(3)!;
      // BCV uses comma as decimal separator (European format).
      final rate = double.tryParse(rateStr.replaceAll(',', '.'));
      if (rate != null && rate > 0) {
        rawRates[iso] = rate;
      }
    }

    print('[BCV-VE] Raw rates: $rawRates');
    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) {
      return null;
    }

    rawRates['VES'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'CNY', 'EUR', 'RUB', 'TRY', 'USD', 'VES',
  ];
}

class BceaoProvider implements CurrencyProvider {
  @override
  String get id => 'bceao';

  @override
  String get name => 'Central Bank of West African States';

  @override
  String get initials => 'BCEAO';

  static final _rowPattern = RegExp(
    r'<td>([^<]+)</td>\s*<td>([^<]+)</td>\s*<td>([^<]+)</td>',
    caseSensitive: false,
  );

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now().toUtc();
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        final response = await http.get(
          Uri.https(
            'www.bceao.int',
            '/en/cours/get_all_devise_by_date',
            {'dateJour': dateStr},
          ),
        );

        if (response.statusCode != 200) {
          print('[BCEAO] Date $dateStr: status=${response.statusCode}');
          continue;
        }

        final body = response.body;
        final rawRates = <String, double>{};

        for (final match in _rowPattern.allMatches(body)) {
          var isoCode = match.group(1)!.trim().toUpperCase();
          final purchaseStr = match.group(2)!.trim();
          final saleStr = match.group(3)!.trim();

          // Fix typo in BCEAO HTML
          if (isoCode == 'GPB') isoCode = 'GBP';

          // Parse rates (comma is decimal separator)
          final purchase = double.tryParse(purchaseStr.replaceAll(',', '.'));
          final sale = double.tryParse(saleStr.replaceAll(',', '.'));
          if (purchase == null || sale == null || purchase == 0) continue;

          // Use average of purchase and sale as the representative rate
          rawRates[isoCode] = (purchase + sale) / 2.0;
        }

        print('[BCEAO] Parsed ${rawRates.length} raw rates for $dateStr');
        if (rawRates.isNotEmpty) {
          rawRates['XOF'] = 1.0;
          final normalized = _normalizeToEurBase(rawRates);
          print('[BCEAO] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      print('[BCEAO] ERROR: No rates found in last 7 days');
    } catch (e, st) {
      print('[BCEAO] ERROR: $e');
      print('[BCEAO] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'JPY', 'USD', 'XOF',
  ];
}
class BcraProvider implements CurrencyProvider {
  @override
  String get id => 'bcra';

  @override
  String get name => 'Banco Central de la República Argentina';

  @override
  String get initials => 'BCRA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCRA] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'api.bcra.gob.ar',
          '/estadisticascambiarias/v1.0/Cotizaciones',
        ),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json,*/*',
        },
      ).timeout(const Duration(seconds: 15));

      print('[BCRA] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final results = jsonData['results'];
        if (results == null) {
          print('[BCRA] ERROR: No results in response');
          return null;
        }

        final detalle = results['detalle'];
        if (detalle is! List) {
          print('[BCRA] ERROR: detalle is not a List');
          return null;
        }

        final rawRates = <String, double>{};

        for (final item in detalle) {
          if (item is! Map) continue;

          var isoCode = (item['codigoMoneda'] as String?)?.trim().toUpperCase();
          final tipoCotizacion = item['tipoCotizacion'];

          if (isoCode == null || isoCode.isEmpty) continue;
          if (tipoCotizacion == null) continue;

          final rate = (tipoCotizacion is num)
              ? tipoCotizacion.toDouble()
              : double.tryParse(tipoCotizacion.toString());
          if (rate == null || rate == 0) continue;

          // BCRA uses MXP for Mexican Peso, map to standard MXN
          if (isoCode == 'MXP') isoCode = 'MXN';

          rawRates[isoCode] = rate;
        }

        print('[BCRA] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['ARS'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BCRA] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BCRA] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BCRA] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCRA] ERROR: $e');
      print('[BCRA] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'ARS', 'AUD', 'BOB', 'BRL', 'CAD', 'CHF', 'CLP', 'CNH', 'CNY', 'COP',
    'CZK', 'DKK', 'EUR', 'GBP', 'HKD', 'ILS', 'INR', 'JPY', 'MXN', 'NOK',
    'NZD', 'PEN', 'PYG', 'RUB', 'SEK', 'SGD', 'TRY', 'USD', 'UYU', 'VND',
    'XDR', 'ZAR',
  ];
}
class BoaProvider implements CurrencyProvider {
  @override
  String get id => 'boa';

  @override
  String get name => 'Bank of Albania';

  @override
  String get initials => 'BOA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(
            Uri.parse('https://www.bankofalbania.org/Markets/Official_exchange_rate/'),
          )
          .timeout(const Duration(seconds: 15));

      print('[BOA] Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('[BOA] ERROR: GET failed with ${response.statusCode}');
        return null;
      }

      final rawRates = parseBoaHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) {
        print('[BOA] ERROR: parseBoaHtml returned null or empty');
        return null;
      }

      rawRates['ALL'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[BOA] Normalized rates count: ${normalized.length}');
      return normalized;
    } on TimeoutException catch (e) {
      print('[BOA] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOA] ERROR: $e');
      print('[BOA] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseBoaHtml(String html) {
    final rawRates = <String, double>{};

    // Match table rows: <tr>...<td>Currency Name</td><td>ISO</td><td>Rate</td>...
    final rowRegex = RegExp(
      r'<tr[^>]*>\s*<t[dh][^>]*>([^<]+)</t[dh]>\s*<t[dh][^>]*>([A-Z]{3})</t[dh]>\s*<t[dh][^>]*>([0-9.,]+)</t[dh]>',
      caseSensitive: false,
      dotAll: true,
    );

    const skipCurrencies = {'SDR', 'XAU', 'XAG'};

    for (final match in rowRegex.allMatches(html)) {
      final name = match.group(1)!.trim();
      final iso = match.group(2)!.toUpperCase();
      final rateStr = match.group(3)!;

      if (skipCurrencies.contains(iso)) continue;

      final rate = double.tryParse(rateStr.replaceAll(',', ''));
      if (rate == null || rate == 0) continue;

      // JPY is quoted per 100 units (e.g. "Japanese Yen   (100)").
      if (name.contains('(100)')) {
        rawRates[iso] = rate / 100.0;
      } else {
        rawRates[iso] = rate;
      }
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) {
      return null;
    }

    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNH', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP', 'HUF',
    'JPY', 'MKD', 'NOK', 'RUB', 'SEK', 'TRY', 'USD', 'ALL',
  ];
}

class BcuProvider implements CurrencyProvider {
  @override
  String get id => 'bcu';

  @override
  String get name => 'Banco Central del Uruguay';

  @override
  String get initials => 'BCU';

  // Known BCU currency IDs (discovered by scanning the SOAP service)
  static const _currencyIds = [
    2,     // XDR
    105,   // AUD
    500,   // ARS
    1000,  // BRL
    1111,  // EUR
    1300,  // CLP
    1490,  // NZD
    1620,  // ZAR
    1800,  // DKK
    2222,  // USD
    2309,  // CAD
    2700,  // GBP
    3600,  // JPY
    4000,  // PEN
    4150,  // CNY
    4155,  // CNH
    4200,  // MXN
    4300,  // HUF
    4400,  // TRY
    4600,  // NOK
    4800,  // PYG
    4900,  // ISK
    5100,  // HKD
    5300,  // KRW
    5400,  // RUB
    5500,  // COP
    5600,  // MYR
    5700,  // INR
    5800,  // SEK
    5900,  // CHF
    6200,  // VEF (old Venezuelan bolivar)
  ];

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BCU] Starting fetchRates()');
    try {
      // Build SOAP request body template (currency IDs are static)
      final itemsBuffer = StringBuffer();
      for (final id in _currencyIds) {
        itemsBuffer.write('<item>$id</item>');
      }

      // BCU doesn't publish on weekends/holidays; scan backwards up to 7 days
      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final date = DateTime.now().subtract(Duration(days: dayOffset));
        final fecha = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        final soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <soap:Body>
    <wsbcucotizaciones.Execute xmlns="Cotiza">
      <Entrada>
        <Moneda>$itemsBuffer</Moneda>
        <FechaDesde>$fecha</FechaDesde>
        <FechaHasta>$fecha</FechaHasta>
        <Grupo>0</Grupo>
      </Entrada>
    </wsbcucotizaciones.Execute>
  </soap:Body>
</soap:Envelope>''';

        final response = await http.post(
          Uri.https('cotizaciones.bcu.gub.uy', '/wscotizaciones/servlet/awsbcucotizaciones'),
          headers: {
            'Content-Type': 'text/xml; charset=utf-8',
            'SOAPAction': 'Cotizaaction/AWSBCUCOTIZACIONES.Execute',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
          body: soapBody,
        ).timeout(const Duration(seconds: 20));

        print('[BCU] Date $fecha: status=${response.statusCode}, len=${response.body.length}');

        if (response.statusCode != 200) continue;

        final document = XmlDocument.parse(response.body);
        final rawRates = <String, double>{};

        // Find all datoscotizaciones.dato elements
        final datos = document.findAllElements('datoscotizaciones.dato');
        for (final dato in datos) {
          final codigoIsoElement = dato.findAllElements('CodigoISO').firstOrNull;
          final tccElement = dato.findAllElements('TCC').firstOrNull;

          if (codigoIsoElement == null || tccElement == null) continue;

          var isoCode = codigoIsoElement.innerText.trim().toUpperCase();
          final tccStr = tccElement.innerText.trim();

          if (isoCode.isEmpty || tccStr.isEmpty) continue;

          // Skip non-standard / non-ISO codes
          if (isoCode == 'DLS.' || isoCode == 'U\$A' || isoCode == 'R\$') continue;

          final rate = double.tryParse(tccStr);
          if (rate == null || rate == 0) continue;

          // Map old Venezuelan bolivar code to current standard
          if (isoCode == 'VEF') isoCode = 'VES';

          // Map SDR to XDR
          if (isoCode == 'SDR') isoCode = 'XDR';

          // BCU uses 'EURO' instead of standard 'EUR'
          if (isoCode == 'EURO') isoCode = 'EUR';

          rawRates[isoCode] = rate;
        }

        print('[BCU] Parsed ${rawRates.length} raw rates for $fecha');
        if (rawRates.isNotEmpty) {
          rawRates['UYU'] = 1.0;

          final normalized = _normalizeToEurBase(rawRates);
          print('[BCU] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      print('[BCU] ERROR: No rates found in last 7 days');
    } on TimeoutException catch (e) {
      print('[BCU] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCU] ERROR: $e');
      print('[BCU] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'ARS', 'AUD', 'BRL', 'CAD', 'CHF', 'CLP', 'CNH', 'CNY', 'COP', 'DKK',
    'EUR', 'GBP', 'HKD', 'HUF', 'INR', 'ISK', 'JPY', 'KRW', 'MXN', 'MYR',
    'NOK', 'NZD', 'PEN', 'PYG', 'RUB', 'SEK', 'TRY', 'USD', 'UYU', 'VES',
    'XDR', 'ZAR',
  ];
}
class BcvProvider implements CurrencyProvider {
  @override
  String get id => 'bcv';

  @override
  String get name => 'Bank of Cape Verde';

  @override
  String get initials => 'BCV';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final client = _createPermissiveClient();
      for (var i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr =
            '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';

        final response = await client.get(
          Uri.https(
            'www.bcv.cv',
            '/en/PoliticaMonetaria/EstatisticasCambiais/Paginas/Estatisticas_Cambiais.aspx',
            {
              '_sd': dateStr,
              '_fd': dateStr,
              '_mdrange': '$dateStr-$dateStr',
              '_refd': dateStr,
              '_expType': 'XML',
            },
          ),
        ).timeout(const Duration(seconds: 15));

        print('[BCV] Response status for $dateStr: ${response.statusCode}');
        if (response.statusCode != 200) continue;

        final document = XmlDocument.parse(response.body);
        final rawRates = <String, double>{};

        for (final result in document.findAllElements('RESULT')) {
          final currency =
              result.findElements('Currency').firstOrNull?.innerText;
          final unitsStr =
              result.findElements('Units').firstOrNull?.innerText;
          final purchaseStr =
              result.findElements('Purchase').firstOrNull?.innerText;
          final saleStr =
              result.findElements('Sale').firstOrNull?.innerText;

          if (currency == null || purchaseStr == null || saleStr == null) {
            continue;
          }

          final units = int.tryParse(unitsStr ?? '1') ?? 1;
          if (units == 0) continue;

          // The BCV XML uses comma as decimal separator and may contain
          // non-breaking spaces (e.g. "11 929,63700").
          final purchase = double.tryParse(
            purchaseStr
                .replaceAll('\u00A0', '')
                .replaceAll(',', '.'),
          );
          final sale = double.tryParse(
            saleStr
                .replaceAll('\u00A0', '')
                .replaceAll(',', '.'),
          );

          if (purchase == null || sale == null || purchase == 0) continue;

          // Average of purchase/sale, scaled by units.
          rawRates[currency] = ((purchase + sale) / 2.0) / units;
        }

        print('[BCV] Parsed ${rawRates.length} raw rates for $dateStr');
        if (rawRates.containsKey('EUR')) {
          rawRates['CVE'] = 1.0;
          client.close();
          final normalized = _normalizeToEurBase(rawRates);
          print('[BCV] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      client.close();
      print('[BCV] ERROR: No valid data found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[BCV] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BCV] ERROR: $e');
      print('[BCV] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'BRL', 'CAD', 'CHF', 'CNY', 'CVE', 'DKK', 'EUR', 'GBP', 'JPY', 'NOK',
    'SEK', 'USD', 'XOF', 'ZAR',
  ];
}
class BnbProvider implements CurrencyProvider {
  @override
  String get id => 'bnb';

  @override
  String get name => 'Bulgarian National Bank';

  @override
  String get initials => 'BNB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BNB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'www.bnb.bg',
          '/Statistics/StExternalSector/StExchangeRates/StERForeignCurrencies/',
          {'download': 'xml', 'lang': 'EN'},
        ),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/xml,text/xml,*/*',
        },
      ).timeout(const Duration(seconds: 15));

      print('[BNB] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);
        final rawRates = <String, double>{};

        final rows = document.findAllElements('ROW');
        for (final row in rows) {
          final codeElement = row.getElement('CODE');
          final rateElement = row.getElement('RATE');

          if (codeElement == null || rateElement == null) continue;

          final isoCode = codeElement.innerText.trim().toUpperCase();
          final rateStr = rateElement.innerText.trim();

          // Skip header row
          if (isoCode == 'CODE' || isoCode.isEmpty || rateStr.isEmpty) continue;

          final rate = double.tryParse(rateStr);
          if (rate == null || rate == 0) continue;

          rawRates[isoCode] = rate;
        }

        print('[BNB] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['EUR'] = 1.0;

        print('[BNB] Returning ${rawRates.length} rates (EUR-based)');
        return rawRates;
      }
      print('[BNB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BNB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BNB] ERROR: $e');
      print('[BNB] Stack: $st');
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

class BrbProvider implements CurrencyProvider {
  @override
  String get id => 'brb';

  @override
  String get name => 'Banque de la République du Burundi';

  @override
  String get initials => 'BRB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final response = await http.get(
        Uri.parse(
          'https://www.brb.bi/Details%20Taux%20de%20Change?field_code_value=&field_date_value%5Bdate%5D=$dateStr',
        ),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseBrbHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['BIF'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBrbHtml(String html) {
    final rawRates = <String, double>{};

    final rowRegex = RegExp(
      r'<tr[^>]*>\s*<td[^>]*>.*?<a[^>]*>([A-Z]{3})</a>.*?</td>\s*<td[^>]*>\s*([0-9.,]+)\s*</td>\s*<td[^>]*>\s*([0-9.,]+)\s*</td>\s*<td[^>]*>\s*([0-9.,]+)\s*</td>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in rowRegex.allMatches(html)) {
      var iso = match.group(1)!.toUpperCase();
      final rateStr = match.group(3)!; // Taux Moyen (average rate)

      // Map DTS (French: Droits de Tirage Spéciaux) to XDR
      if (iso == 'DTS') iso = 'XDR';

      final rate = double.tryParse(rateStr.trim());
      if (rate == null || rate == 0) continue;

      rawRates[iso] = rate;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) {
      return null;
    }

    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'BIF', 'EUR', 'USD', 'XDR',
  ];
}

class BogProvider implements CurrencyProvider {
  @override
  String get id => 'bog';

  @override
  String get name => 'Bank of Guyana';

  @override
  String get initials => 'BOG';

  static final _rowPattern = RegExp(
    r'<tr>\s*<td[^>]*>.*?</td>\s*<td[^>]*>.*?<span class="tabs">([A-Z]{3})</span>.*?</td>\s*<td[^>]*>.*?<span class="tabs">([0-9.]*)</span>.*?</td>\s*<td[^>]*>.*?<span class="tabs">([0-9.]*)',
    dotAll: true,
    caseSensitive: false,
  );

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.https('bankofguyana.org.gy', '/bog/'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64; rv:150.0) Gecko/20100101 Firefox/150.0',
        },
      ).timeout(const Duration(seconds: 15));

      print('[BOG] Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('[BOG] ERROR: GET failed with ${response.statusCode}');
        return null;
      }

      final body = response.body;
      final rawRates = <String, double>{};

      for (final match in _rowPattern.allMatches(body)) {
        final currency = match.group(1)!;
        final buyStr = match.group(2)!.trim();
        final sellStr = match.group(3)!.trim();

        final buy = double.tryParse(buyStr);
        if (buy == null || buy == 0) continue;

        final sell = double.tryParse(sellStr);
        if (sell != null && sell > 0) {
          rawRates[currency] = (buy + sell) / 2.0;
        } else {
          rawRates[currency] = buy;
        }
      }

      print('[BOG] Parsed ${rawRates.length} raw rates');
      if (!rawRates.containsKey('EUR')) {
        print('[BOG] ERROR: Missing EUR rate');
        return null;
      }

      rawRates['GYD'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[BOG] Normalized rates count: ${normalized.length}');
      return normalized;
    } on TimeoutException catch (e) {
      print('[BOG] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOG] ERROR: $e');
      print('[BOG] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'BBD', 'BZD', 'CAD', 'EUR', 'GBP', 'GYD', 'JMD', 'TTD', 'USD', 'XCD',
  ];
}
class BojProvider implements CurrencyProvider {
  @override
  String get id => 'boj';

  @override
  String get name => 'Bank of Japan';

  @override
  String get initials => 'BOJ';

  /// Extracts the latest non-null value from a BOJ time-series response.
  double? _latestValue(Map<String, dynamic> series) {
    final valuesObj = series['VALUES'];
    if (valuesObj is! Map) return null;

    final dates = valuesObj['SURVEY_DATES'];
    final values = valuesObj['VALUES'];
    if (dates is! List || values is! List) return null;
    if (dates.length != values.length) return null;

    for (var i = dates.length - 1; i >= 0; i--) {
      final val = values[i];
      if (val != null && val is num) {
        return val.toDouble();
      }
    }
    return null;
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BOJ] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final year = now.year;
      final month = now.month.toString().padLeft(2, '0');
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      final prevMonth = now.month == 1 ? '12' : (now.month - 1).toString().padLeft(2, '0');

      final response = await http.get(
        Uri.https(
          'www.stat-search.boj.or.jp',
          '/api/v1/getDataCode',
          {
            'format': 'json',
            'lang': 'en',
            'db': 'FM08',
            'code': 'FXERD01,FXERD31',
            'startDate': '$prevYear$prevMonth',
            'endDate': '$year$month',
          },
        ),
      ).timeout(const Duration(seconds: 15));

      print('[BOJ] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);

        if (jsonData['STATUS'] != 200) {
          print('[BOJ] ERROR: API status ${jsonData['STATUS']}');
          return null;
        }

        final resultSet = jsonData['RESULTSET'];
        if (resultSet is! List) {
          print('[BOJ] ERROR: RESULTSET is not a List');
          return null;
        }

        double? usdJpy; // FXERD01: JPY per USD
        double? eurUsd; // FXERD31: USD per EUR

        for (final series in resultSet) {
          if (series is! Map) continue;
          final seriesMap = series as Map<String, dynamic>;
          final code = seriesMap['SERIES_CODE'] as String?;
          if (code == null) continue;

          final value = _latestValue(seriesMap);
          if (value == null || value == 0) continue;

          if (code == 'FXERD01') {
            usdJpy = value;
          } else if (code == 'FXERD31') {
            eurUsd = value;
          }
        }

        print('[BOJ] USD/JPY: $usdJpy, EUR/USD: $eurUsd');

        if (usdJpy == null || eurUsd == null) {
          print('[BOJ] ERROR: Missing required series');
          return null;
        }

        final rawRates = <String, double>{
          'JPY': 1.0, // base currency
          'USD': usdJpy, // JPY per USD
          'EUR': eurUsd * usdJpy, // JPY per EUR = USD per EUR * JPY per USD
        };

        final normalized = _normalizeToEurBase(rawRates);
        print('[BOJ] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BOJ] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BOJ] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOJ] ERROR: $e');
      print('[BOJ] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => ['EUR', 'JPY', 'USD'];
}
class BokProvider implements CurrencyProvider {
  @override
  String get id => 'bok';

  @override
  String get name => 'Bank of Korea';

  @override
  String get initials => 'BOK';

  // Map BOK item codes to ISO codes (more reliable than Korean names)
  static final _codeToIso = {
    '0000001': 'USD',
    '0000002': 'JPY',
    '0000003': 'EUR',
    '0000012': 'GBP',
    '0000013': 'CAD',
    '0000014': 'CHF',
    '0000015': 'HKD',
    '0000016': 'SEK',
    '0000017': 'AUD',
    '0000018': 'DKK',
  };

  static final _perUnitPattern = RegExp(r'\((\d+)(?:엔|루피아|동)\)');

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BOK] Starting fetchRates()');
    try {
      // BOK doesn't publish on weekends/holidays; scan backwards up to 7 days
      for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
        final date = DateTime.now().subtract(Duration(days: dayOffset));
        final dateStr = '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

        final response = await http.get(
          Uri.https(
            'ecos.bok.or.kr',
            '/api/StatisticSearch/sample/json/kr/1/10/731Y001/D/$dateStr/$dateStr',
          ),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 15));

        print('[BOK] Date $dateStr: status=${response.statusCode}, len=${response.body.length}');

        if (response.statusCode != 200) continue;

        final jsonData = jsonDecode(response.body);
        final rows = jsonData['StatisticSearch']?['row'];
        if (rows is! List) {
          print('[BOK] ERROR: No row data in response');
          continue;
        }

        final rawRates = <String, double>{};

        for (final item in rows) {
          if (item is! Map) continue;

          final itemCode = item['ITEM_CODE1'] as String?;
          final itemName = item['ITEM_NAME1'] as String?;
          final dataValue = item['DATA_VALUE'];

          if (itemCode == null || dataValue == null) continue;

          final isoCode = _codeToIso[itemCode];
          if (isoCode == null) {
            // Try to detect unknown currencies dynamically
            print('[BOK] Unknown item code: $itemCode, name: $itemName');
            continue;
          }

          final rate = (dataValue is num)
              ? dataValue.toDouble()
              : double.tryParse(dataValue.toString());
          if (rate == null || rate == 0) continue;

          // Check for per-unit scaling (e.g. "(100엔)")
          if (itemName != null) {
            final match = _perUnitPattern.firstMatch(itemName);
            if (match != null) {
              final unit = int.tryParse(match.group(1)!);
              if (unit != null && unit > 0) {
                rawRates[isoCode] = rate / unit;
                continue;
              }
            }
          }

          rawRates[isoCode] = rate;
        }

        print('[BOK] Parsed ${rawRates.length} raw rates for $dateStr');
        if (rawRates.isNotEmpty) {
          rawRates['KRW'] = 1.0;

          final normalized = _normalizeToEurBase(rawRates);
          print('[BOK] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      print('[BOK] ERROR: No rates found in last 7 days');
    } on TimeoutException catch (e) {
      print('[BOK] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOK] ERROR: $e');
      print('[BOK] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'HKD', 'JPY', 'KRW', 'SEK',
    'USD',
  ];
}
class BomProvider implements CurrencyProvider {
  @override
  String get id => 'bom';

  @override
  String get name => 'Bank of Mongolia';

  @override
  String get initials => 'BOM';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year - 1, now.month, now.day);
      final startStr =
          '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      final endStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http.post(
        Uri.parse(
          'https://www.mongolbank.mn/en/currency-rates/data?startDate=$startStr&endDate=$endStr',
        ),
      );

      if (response.statusCode != 200) {
        print('[BOM] HTTP ${response.statusCode}');
        return null;
      }

      return parseBomJson(response.body);
    } catch (e, st) {
      print('[BOM] ERROR: $e');
      print('[BOM] Stack: $st');
    }
    return null;
  }

  /// Parses the BOM JSON response and returns EUR-normalized rates.
  @visibleForTesting
  Map<String, double>? parseBomJson(String jsonText) {
    final jsonData = jsonDecode(jsonText);
    final data = jsonData['data'];
    if (data is! List || data.isEmpty) {
      print('[BOM] No data in response');
      return null;
    }

    // Use the last (most recent) entry
    final latest = data.last as Map<String, dynamic>;
    final rawRates = <String, double>{};

    // Skip non-currency and metadata entries
    final skipKeys = {'RATE_DATE'};

    for (final entry in latest.entries) {
      final key = entry.key;
      if (skipKeys.contains(key)) continue;

      final valueStr = entry.value?.toString();
      if (valueStr == null || valueStr.isEmpty) continue;

      // Remove commas from values like "3,570.82"
      final cleaned = valueStr.replaceAll(',', '');
      final rate = double.tryParse(cleaned);
      if (rate == null || rate <= 0) continue;

      rawRates[key] = rate;
    }

    print('[BOM] Parsed ${rawRates.length} raw rates');
    if (rawRates.isEmpty) return null;

    rawRates['MNT'] = 1.0;
    final normalized = _normalizeToEurBase(rawRates);
    print('[BOM] Normalized rates count: ${normalized.length}');
    return normalized;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BGN', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK', 'EGP', 'GBP',
    'HKD', 'HUF', 'IDR', 'INR', 'JPY', 'KRW', 'KWD', 'KZT', 'MYR', 'NOK',
    'NZD', 'PLN', 'RUB', 'SEK', 'SGD', 'THB', 'TRY', 'TWD', 'UAH', 'USD',
    'VND', 'ZAR', 'MNT',
  ];
}
class BotProvider implements CurrencyProvider {
  @override
  String get id => 'bot';

  @override
  String get name => 'Bank of Thailand';

  @override
  String get initials => 'BOT';

  static final _perUnitPattern = RegExp(r'\(per\s+(\d[\d,]*)\s+.*?\)', caseSensitive: false);
  static final _parenNumberPattern = RegExp(r'\((\d[\d,]*)\s+.*?\)');

  int _extractMultiplier(String countryName) {
    // Match "(per 100 yen)" or "(per 1,000 rupiah)"
    final match = _perUnitPattern.firstMatch(countryName);
    if (match != null) {
      final numStr = match.group(1)!.replaceAll(',', '');
      return int.tryParse(numStr) ?? 1;
    }
    // Match "(100 Riel)" without "per"
    final match2 = _parenNumberPattern.firstMatch(countryName);
    if (match2 != null) {
      final numStr = match2.group(1)!.replaceAll(',', '');
      return int.tryParse(numStr) ?? 1;
    }
    return 1;
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BOT] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'www.bot.or.th',
          '/content/bot/en/statistics/exchange-rate/jcr:content/root/container/statisticstable2.results.level3cache.json',
        ),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': '*/*',
          'Referer': 'https://www.bot.or.th/en/statistics/exchange-rate.html',
        },
      ).timeout(const Duration(seconds: 15));

      print('[BOT] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final ratesList = jsonData['responseContent'];
        if (ratesList is! List) {
          print('[BOT] ERROR: responseContent is not a List');
          return null;
        }

        final rawRates = <String, double>{};

        for (final item in ratesList) {
          if (item is! Map) continue;

          final currencyId = item['currency_id'] as String?;
          final rateStr = item['buying_transfer'] as String?;
          final countryName = item['countryName'] as String?;

          if (currencyId == null || rateStr == null || countryName == null) continue;
          if (rateStr == '-') continue;

          final rate = double.tryParse(rateStr);
          if (rate == null || rate == 0) continue;

          final multiplier = _extractMultiplier(countryName);
          if (multiplier == 0) continue;

          // Rate is THB per <multiplier> units of foreign currency
          rawRates[currencyId] = rate / multiplier;
        }

        print('[BOT] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['THB'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[BOT] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[BOT] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[BOT] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BOT] ERROR: $e');
      print('[BOT] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BDT', 'BHD', 'BND', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK',
    'EGP', 'EUR', 'GBP', 'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'JOD', 'JPY',
    'KES', 'KHR', 'KRW', 'KWD', 'LAK', 'LKR', 'MXN', 'MYR', 'MMK', 'NOK',
    'NPR', 'NZD', 'OMR', 'PGK', 'PHP', 'PKR', 'PLN', 'QAR', 'RUB', 'SAR',
    'SEK', 'SGD', 'THB', 'TWD', 'VND', 'ZAR',
  ];
}
class BslProvider implements CurrencyProvider {
  @override
  String get id => 'bsl';

  @override
  String get name => 'Bank of Sierra Leone';

  @override
  String get initials => 'BSL';

  static final _nameToIso = <String, String>{
    'POUND STERLING': 'GBP',
    'U.S. DOLLAR': 'USD',
    'CANADIAN DOLLAR': 'CAD',
    'SWISS FRANC': 'CHF',
    'SWEDISH KRONER': 'SEK',
    'JAPANESE YEN': 'JPY',
    'NORWEGIAN KRONE': 'NOK',
    'EURO': 'EUR',
    'DANISH KRONE': 'DKK',
    'AUSTRALIAN DOLLAR': 'AUD',
    'SAUDI RIYAL': 'SAR',
    'KUWAIT DINAH': 'KWD',
    'U.A.E.DIRHAMS': 'AED',
    'U.A.E. DIRHAM': 'AED',
    'U.A.E.DIRHAM': 'AED',
    'SOUTH AFRICAN RAND': 'ZAR',
    'CHINESE RENMINBI': 'CNY',
    'HONG KONG': 'HKD',
    'S.D.R.': 'XDR',
    'CFA FRANC': 'XOF',
    'GAMBIAN DALASI': 'GMD',
    'GUINEAN FRANC': 'GNF',
    'GHANABANK CEDI': 'GHS',
    'NAIRA': 'NGN',
    'CENTRAL BANK LIBERIA': 'LRD',
    'CABO VERDE ESCUDOS': 'CVE',
  };

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[BSL] Starting fetchRates()');
    try {
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dd = date.day.toString().padLeft(2, '0');
        final mm = date.month.toString().padLeft(2, '0');
        final yyyy = date.year;
        final url =
            'https://bsl.gov.sl/Indicative%20Exchange%20Rates%20-$dd-$mm-$yyyy.pdf';

        print('[BSL] Trying $url');
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 &&
            response.bodyBytes.length > 4 &&
            String.fromCharCodes(response.bodyBytes.sublist(0, 4)) == '%PDF') {
          print('[BSL] Got PDF');
          final text = _extractPdfText(response.bodyBytes);
          final result = parseBslPdfText(text);
          print('[BSL] Parsed result: ${result != null ? '${result.length} rates' : 'null'}');
          return result;
        }
      }
      print('[BSL] No PDF found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[BSL] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[BSL] ERROR: $e');
      print('[BSL] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseBslPdfText(String text) {
    final rawRates = <String, double>{};

    // Match known currency names followed by a numeric rate.
    // Some PDF extraction lines contain two column entries concatenated,
    // e.g. "POUND STERLING 30.7687 U.S. DOLLAR 22.7925".
    // We build a regex that matches every occurrence of (name, number).
    final namePattern = _nameToIso.keys.map(RegExp.escape).join('|');
    final regex = RegExp(
      '($namePattern)\\s+([0-9]+\\.[0-9]+)',
      caseSensitive: false,
    );

    for (final match in regex.allMatches(text)) {
      final name = match.group(1)!.toUpperCase();
      final rateStr = match.group(2)!;
      final iso = _nameToIso[name];
      if (iso == null) continue;

      final rate = double.tryParse(rateStr);
      if (rate == null || rate == 0) continue;

      // Keep the first (reference-rates section) occurrence
      if (!rawRates.containsKey(iso)) {
        rawRates[iso] = rate;
      }
    }

    if (!rawRates.containsKey('EUR')) {
      print('[BSL] ERROR: EUR rate not found in PDF text');
      return null;
    }

    // SLE itself: 1 SLE = 1 SLE
    rawRates['SLE'] = 1.0;

    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'CVE', 'DKK', 'EUR', 'GBP', 'GHS', 'GMD',
    'GNF', 'HKD', 'JPY', 'KWD', 'LRD', 'NGN', 'NOK', 'SAR', 'SEK', 'SLE',
    'USD', 'XDR', 'XOF', 'ZAR',
  ];
}

class BsiProvider implements CurrencyProvider {
  @override
  String get id => 'bsi';

  @override
  String get name => 'Bank of Slovenia';

  @override
  String get initials => 'BSI';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.bsi.si/_data/tecajnice/EksotTecBS.xml'),
      );

      if (response.statusCode != 200) {
        print('[BSI] HTTP ${response.statusCode}');
        return null;
      }

      return parseBsiXml(response.body);
    } catch (e, st) {
      print('[BSI] ERROR: $e');
      print('[BSI] Stack: $st');
    }
    return null;
  }

  /// Parses the BSI exotic-rates XML and returns EUR-normalized rates.
  @visibleForTesting
  Map<String, double>? parseBsiXml(String xml) {
    final document = XmlDocument.parse(xml);
    final rawRates = <String, double>{};

    for (final tecaj in document.findAllElements('tecaj')) {
      final oznaka = tecaj.getAttribute('oznaka');
      final valueText = tecaj.innerText;

      if (oznaka == null || valueText.isEmpty) continue;

      final value = double.tryParse(valueText.replaceAll(',', '.'));
      if (value == null || value == 0) continue;

      // Rates are "units of foreign currency per 1 EUR"
      rawRates[oznaka] = value;
    }

    print('[BSI] Parsed ${rawRates.length} raw rates');
    if (rawRates.isNotEmpty) {
      rawRates['EUR'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[BSI] Normalized rates count: ${normalized.length}');
      return normalized;
    }

    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'ALL', 'AMD', 'AOA', 'ARS', 'AWG', 'AZN', 'BAM', 'BBD',
    'BDT', 'BHD', 'BIF', 'BND', 'BOB', 'BRL', 'BSD', 'BTN', 'BWP', 'BZD',
    'CAD', 'CDF', 'CLP', 'COP', 'CRC', 'CUP', 'CVE', 'DJF', 'DOP', 'DZD',
    'EGP', 'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GEL', 'GHS', 'GIP', 'GMD',
    'GNF', 'GTQ', 'GYD', 'HTG', 'HNL', 'IDR', 'IQD', 'IRR', 'JMD', 'JOD',
    'KES', 'KGS', 'KHR', 'KMF', 'KPW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP',
    'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT',
    'MOP', 'MRU', 'MUR', 'MVR', 'MWK', 'MZN', 'NAD', 'NGN', 'NIO', 'NPR',
    'OMR', 'PAB', 'PEN', 'PGK', 'PKR', 'PYG', 'QAR', 'RON', 'RSD', 'RWF',
    'SAR', 'SBD', 'SCR', 'SDG', 'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN',
    'SVC', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TTD', 'TWD',
    'TZS', 'UAH', 'UGX', 'UYU', 'UZS', 'VES', 'VND', 'VUV', 'WST', 'XAF',
    'XAG', 'XAU', 'XCD', 'XDR', 'XOF', 'XPD', 'XPF', 'XPT', 'YER', 'ZAR',
    'ZMW',
  ];
}
class CbkProvider implements CurrencyProvider {
  @override
  String get id => 'cbk';

  @override
  String get name => 'Central Bank of Kenya';

  @override
  String get initials => 'CBK';

  static final _nameToIso = {
    'US DOLLAR': 'USD',
    'SW KRONER': 'SEK',
    'NOR KRONER': 'NOK',
    'DAN KRONER': 'DKK',
    'IND RUPEE': 'INR',
    'HONGKONG DOLLAR': 'HKD',
    'SINGAPORE DOLLAR': 'SGD',
    'SAUDI RIYAL': 'SAR',
    'CHINESE YUAN': 'CNY',
    'JPY (100)': 'JPY',
    'S FRANC': 'CHF',
    'CAN \$': 'CAD',
    'STG POUND': 'GBP',
    'EURO': 'EUR',
    'SA RAND': 'ZAR',
    'AE DIRHAM': 'AED',
    'AUSTRALIAN \$': 'AUD',
  };

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      // wpDataTables requires POST with DataTables parameters
      final uri = Uri.https(
        'www.centralbank.go.ke',
        '/wp-admin/admin-ajax.php',
        {'action': 'get_wdtable', 'table_id': '193'},
      );
      final response = await http.post(
        uri,
        body: {
          'draw': '1',
          'columns[0][data]': '0',
          'columns[0][searchable]': 'true',
          'columns[0][orderable]': 'true',
          'columns[1][data]': '1',
          'columns[1][searchable]': 'true',
          'columns[1][orderable]': 'true',
          'columns[2][data]': '2',
          'columns[2][searchable]': 'true',
          'columns[2][orderable]': 'true',
          'order[0][column]': '0',
          'order[0][dir]': 'desc',
          'start': '0',
          'length': '100',
          'search[value]': '',
        },
      );

      if (response.statusCode != 200) {
        print('[CBK] Response status: ${response.statusCode}');
        return null;
      }

      final jsonData = jsonDecode(response.body);
      final data = jsonData['data'];
      if (data is! List) {
        print('[CBK] No data array in response');
        return null;
      }

      final rawRates = <String, double>{};
      String? latestDate;

      for (final row in data) {
        if (row is! List || row.length < 3) continue;

        final date = row[0] as String?;
        final name = row[1] as String?;
        final rateStr = row[2] as String?;
        if (date == null || name == null || rateStr == null) continue;

        // Only process the most recent date
        if (latestDate == null) {
          latestDate = date;
        } else if (date != latestDate) {
          break;
        }

        // Skip East African cross rates
        if (name.startsWith('KES /')) continue;

        final isoCode = _nameToIso[name];
        if (isoCode == null) {
          print('[CBK] Unknown currency name: $name');
          continue;
        }

        final rate = double.tryParse(rateStr);
        if (rate == null || rate == 0) continue;

        // JPY rate is per 100 yen
        if (name == 'JPY (100)') {
          rawRates[isoCode] = rate / 100.0;
        } else {
          rawRates[isoCode] = rate;
        }
      }

      print('[CBK] Parsed ${rawRates.length} raw rates for date $latestDate');
      if (rawRates.isEmpty) return null;

      rawRates['KES'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[CBK] Normalized rates count: ${normalized.length}');
      return normalized;
    } catch (e, st) {
      print('[CBK] ERROR: $e');
      print('[CBK] Stack: $st');
      return null;
    }
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'HKD', 'INR',
    'JPY', 'KES', 'NOK', 'SAR', 'SEK', 'SGD', 'USD', 'ZAR',
  ];
}
class CbpmrProvider implements CurrencyProvider {
  @override
  String get id => 'cbpmr';

  @override
  String get name => 'Central Bank of the Republic of Transnistria';

  @override
  String get initials => 'CBPMR';

  static final _linePattern = RegExp(
    r'([A-Z]{3}),(\d+),([0-9.]+),\d+$',
    multiLine: true,
  );

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      // Try today and the previous 6 days (weekends/holidays have no data).
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        print('[CBPMR] Trying $dateStr');
        final response = await http.get(
          Uri.https(
            'www.cbpmr.net',
            '/csv.php',
            {
              'vid': 'val',
              'date': dateStr,
              'lang': 'en',
            },
          ),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200 || response.body.trim().isEmpty) {
          print('[CBPMR] No data for $dateStr (status=${response.statusCode}, len=${response.body.length})');
          continue;
        }

        final result = parseCbpmrCsv(response.body);
        if (result != null) {
          print('[CBPMR] Parsed ${result.length} rates from $dateStr');
          return result;
        }
      }
      print('[CBPMR] No valid CSV found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[CBPMR] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBPMR] ERROR: $e');
      print('[CBPMR] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseCbpmrCsv(String csv) {
    final rawRates = <String, double>{};

    for (final match in _linePattern.allMatches(csv)) {
      final currency = match.group(1)!;
      final units = int.parse(match.group(2)!);
      final rate = double.parse(match.group(3)!);

      if (units == 0) continue;
      rawRates[currency] = rate / units;
    }

    print('[CBPMR] Parsed ${rawRates.length} raw rates');
    if (!rawRates.containsKey('EUR')) {
      print('[CBPMR] ERROR: Missing EUR rate');
      return null;
    }

    rawRates['PRB'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AMD', 'AUD', 'AZN', 'BYN', 'CAD', 'CHF', 'CNY', 'CZK', 'DKK',
    'EUR', 'GBP', 'HUF', 'ILS', 'INR', 'JPY', 'KGS', 'KZT', 'MDL', 'NOK',
    'NZD', 'PLN', 'PRB', 'RON', 'RSD', 'RUB', 'SEK', 'TJS', 'TRY', 'UAH',
    'USD',
  ];
}
class CbsProvider implements CurrencyProvider {
  @override
  String get id => 'cbs';

  @override
  String get name => 'Central Bank of Seychelles';

  @override
  String get initials => 'CBS';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.https(
          'www.cbs.sc',
          '/Controller/MarketinfoController.jsp',
          {'type': 'daily rates'},
        ),
      );

      if (response.statusCode != 200) {
        print('[CBS] Response status: ${response.statusCode}');
        return null;
      }

      final jsonData = jsonDecode(response.body);
      final drafts = jsonData['dailybankdrafts'];
      if (drafts is! List || drafts.isEmpty) {
        print('[CBS] No dailybankdrafts data');
        return null;
      }

      final item = drafts[0];
      if (item is! Map) {
        print('[CBS] Invalid draft item');
        return null;
      }

      final rawRates = <String, double>{};

      final usdMid = double.tryParse(item['usdmid']?.toString() ?? '');
      final gbpMid = double.tryParse(item['gbpmid']?.toString() ?? '');
      final eurMid = double.tryParse(item['eurmid']?.toString() ?? '');

      if (usdMid != null && usdMid > 0) rawRates['USD'] = usdMid;
      if (gbpMid != null && gbpMid > 0) rawRates['GBP'] = gbpMid;
      if (eurMid != null && eurMid > 0) rawRates['EUR'] = eurMid;

      print('[CBS] Parsed ${rawRates.length} raw rates');
      if (rawRates.isEmpty) return null;

      rawRates['SCR'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[CBS] Normalized rates count: ${normalized.length}');
      return normalized;
    } catch (e, st) {
      print('[CBS] ERROR: $e');
      print('[CBS] Stack: $st');
      return null;
    }
  }

  @override
  List<String> get supportedCurrencies => [
    'EUR', 'GBP', 'SCR', 'USD',
  ];
}

class CbvsProvider implements CurrencyProvider {
  @override
  String get id => 'cbvs';

  @override
  String get name => 'Centrale Bank van Suriname';

  @override
  String get initials => 'CBVS';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      // Try today and the previous 6 days.
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final yyyy = date.year.toString();
        final yy = (date.year % 100).toString().padLeft(2, '0');
        final mm = date.month.toString().padLeft(2, '0');
        final dd = date.day.toString().padLeft(2, '0');
        final pdfId = 'DO$yy$mm${dd}E';
        final url =
            'https://www.cbvs.sr/images/content/publicaties/Wisselkoersen/$yyyy/$pdfId%2010.00%20uur.pdf';

        print('[CBVS] Trying $url');
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 &&
            response.bodyBytes.length > 4 &&
            String.fromCharCodes(response.bodyBytes.sublist(0, 4)) == '%PDF') {
          print('[CBVS] Got PDF for ${date.toIso8601String().split('T').first}');
          final text = _extractPdfText(response.bodyBytes);
          final result = parseCbvsPdfText(text);
          print('[CBVS] Parsed result: ${result != null ? '${result.length} rates' : 'null'}');
          return result;
        }
      }
      print('[CBVS] No PDF found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[CBVS] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBVS] ERROR: $e');
      print('[CBVS] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseCbvsPdfText(String text) {
    final rawRates = <String, double>{};

    // Matches:
    //   (USD)37.222 37.700
    //   (GYD PER 100 )17.687 18.033
    final regex = RegExp(
      r'\\?\(([A-Z]{3})(?:\s+PER\s+100\s*)?(?:\\?\)|\\)?\s*([0-9.,]+)\s+([0-9.,]+)',
      caseSensitive: false,
    );

    for (final match in regex.allMatches(text)) {
      final code = match.group(1)!.toUpperCase();
      final buyingStr = match.group(2)!;
      final sellingStr = match.group(3)!;

      // Numbers use dot as thousands separator and comma as decimal
      // e.g. "37.222" → 37.222, "37,700" → 37.7
      final buying = double.tryParse(
        buyingStr.replaceAll('.', '').replaceAll(',', '.'),
      );
      final selling = double.tryParse(
        sellingStr.replaceAll('.', '').replaceAll(',', '.'),
      );
      if (buying == null || selling == null || buying == 0) continue;

      var mid = (buying + selling) / 2.0;

      // Some rates are quoted per 100 units (e.g. GYD PER 100).
      if (match.group(0)!.toUpperCase().contains('PER 100')) {
        mid /= 100.0;
      }

      rawRates[code] = mid;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) {
      return null;
    }

    rawRates['SRD'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AWG', 'BBD', 'BRL', 'CNY', 'EUR', 'GBP', 'GYD', 'SRD', 'TTD', 'USD',
    'XCD', 'XCG',
  ];
}

class CentralBankOfIcelandProvider implements CurrencyProvider {
  @override
  String get id => 'central_bank_of_iceland';

  @override
  String get name => 'Central Bank of Iceland';

  @override
  String get initials => 'CBI';

  static const _nameToIso = {
    'Bandaríkjadalur': 'USD',
    'Dönsk króna': 'DKK',
    'Evra': 'EUR',
    'Japanskt jen': 'JPY',
    'Kanadadalur': 'CAD',
    'Norsk króna': 'NOK',
    'Sérstök dráttarréttindi- SDR': 'XDR',
    'Sterlingspund': 'GBP',
    'Svissneskur franki': 'CHF',
    'Sænsk króna': 'SEK',
  };

  DateTime? _parseDate(String dateStr) {
    // Format: "M/d/yyyy h:mm:ss AM" or "MM/dd/yyyy hh:mm:ss AM"
    final parts = dateStr.split(' ');
    if (parts.isEmpty) return null;
    final dateParts = parts[0].split('/');
    if (dateParts.length != 3) return null;
    final month = int.tryParse(dateParts[0]);
    final day = int.tryParse(dateParts[1]);
    final year = int.tryParse(dateParts[2]);
    if (month == null || day == null || year == null) return null;
    return DateTime(year, month, day);
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[CBI] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https(
          'sedlabanki.is',
          '/xmltimeseries/Default.aspx',
          {
            'DagsFra': 'LATEST',
            'GroupID': '9',
            'Type': 'xml',
          },
        ),
      ).timeout(const Duration(seconds: 15));

      print('[CBI] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        // The server returns UTF-8 bytes but doesn't set the charset header,
        // so response.body decodes incorrectly. Decode bytes as UTF-8 explicitly.
        final body = utf8.decode(response.bodyBytes);
        final document = XmlDocument.parse(body);
        final rawRates = <String, double>{};
        final cutoff = DateTime.now().subtract(const Duration(days: 90));

        for (final timeSeries in document.findAllElements('TimeSeries')) {
          final description = timeSeries.findElements('Description').firstOrNull?.innerText;
          if (description == null || !description.contains('miðgengi')) continue;

          final name = timeSeries.findElements('Name').firstOrNull?.innerText;
          if (name == null) continue;

          final isoCode = _nameToIso[name];
          if (isoCode == null) continue;

          final entry = timeSeries.findElements('TimeSeriesData').firstOrNull
              ?.findElements('Entry').firstOrNull;
          if (entry == null) continue;

          final dateStr = entry.findElements('Date').firstOrNull?.innerText;
          final valueStr = entry.findElements('Value').firstOrNull?.innerText;

          if (dateStr == null || valueStr == null) continue;

          final date = _parseDate(dateStr);
          if (date == null || date.isBefore(cutoff)) continue;

          final value = double.tryParse(valueStr);
          if (value == null || value == 0) continue;

          // Rate is ISK per unit of foreign currency
          rawRates[isoCode] = value;
        }

        print('[CBI] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['ISK'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[CBI] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[CBI] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[CBI] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[CBI] ERROR: $e');
      print('[CBI] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'ISK', 'JPY', 'NOK', 'SEK', 'USD',
    'XDR',
  ];
}
class EccbProvider implements CurrencyProvider {
  @override
  String get id => 'eccb';

  @override
  String get name => 'Eastern Caribbean Central Bank';

  @override
  String get initials => 'ECCB';

  static final _blockPattern = RegExp(
    r'<div class="exchange-rates-data[^"]*">(.*?)(?=<div class="exchange-rates-data[^"]*">|\s*$)',
    dotAll: true,
    caseSensitive: false,
  );

  static final _itemPattern = RegExp(
    r'<span class="fi fis fi-[a-z]{2}" title="([^"]*)">.*?</span>.*?<div class="value">\s*([0-9.]+)\s*</div>',
    dotAll: true,
    caseSensitive: false,
  );

  static const _countryToCurrency = {
    'Australia': 'AUD',
    'Canada': 'CAD',
    'Europe': 'EUR',
    'Denmark': 'DKK',
    'Japan': 'JPY',
    'New Zealand': 'NZD',
    'Norway': 'NOK',
    'Sweden': 'SEK',
    'Switzerland': 'CHF',
    'United Kingdom': 'GBP',
    'China': 'CNY',
    'United States': 'USD',
    'Kuwait': 'KWD',
    'South Korea': 'KRW',
    'United Arab Emirates': 'AED',
    'Barbados': 'BBD',
    'Belize': 'BZD',
    'Guyana': 'GYD',
    'Jamaica': 'JMD',
    'Trinidad and Tobago': 'TTD',
  };

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String? _extractCookie(String setCookieValue, String cookieName) {
    final pattern = RegExp('$cookieName=([^;]+)');
    final match = pattern.firstMatch(setCookieValue);
    return match?.group(1);
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      final monthYear = '${_months[now.month - 1]}-${now.year}';

      // Step 1: GET the page to establish session and extract CSRF token
      final getResponse = await http.get(
        Uri.https('www.eccb-centralbank.org', '/exchange-rates'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64; rv:150.0) Gecko/20100101 Firefox/150.0',
          'Accept': 'text/html',
        },
      ).timeout(const Duration(seconds: 15));

      print('[ECCB] GET status: ${getResponse.statusCode}');
      if (getResponse.statusCode != 200) {
        print('[ECCB] ERROR: GET failed: ${getResponse.statusCode}');
        return null;
      }

      final htmlBody = getResponse.body;

      // Extract CSRF token from meta tag
      final csrfMatch = RegExp(
        r'<meta name="csrf-token" content="([^"]+)">',
        caseSensitive: false,
      ).firstMatch(htmlBody);
      if (csrfMatch == null) {
        print('[ECCB] ERROR: CSRF token not found in HTML');
        return null;
      }
      final csrfToken = csrfMatch.group(1)!;

      // Extract cookies from Set-Cookie headers
      final setCookieHeaders = getResponse.headers['set-cookie'];
      if (setCookieHeaders == null) {
        print('[ECCB] ERROR: No Set-Cookie header');
        return null;
      }
      final xsrfToken = _extractCookie(setCookieHeaders, 'XSRF-TOKEN');
      final session = _extractCookie(
        setCookieHeaders,
        'eastern_caribbean_central_bank_session',
      );
      if (xsrfToken == null || session == null) {
        print('[ECCB] ERROR: Missing required cookies');
        return null;
      }
      final cookieHeader =
          'XSRF-TOKEN=$xsrfToken; eastern_caribbean_central_bank_session=$session';

      // Step 2: POST with CSRF token and cookies
      final postResponse = await http.post(
        Uri.https('www.eccb-centralbank.org', '/exchange-rates'),
        headers: {
          'Content-Type':
              'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-CSRF-TOKEN': csrfToken,
          'Origin': 'https://www.eccb-centralbank.org',
          'Referer': 'https://www.eccb-centralbank.org/exchange-rates',
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64; rv:150.0) Gecko/20100101 Firefox/150.0',
          'Cookie': cookieHeader,
        },
        body: 'date=$monthYear',
      ).timeout(const Duration(seconds: 20));

      print('[ECCB] POST status: ${postResponse.statusCode}');
      if (postResponse.statusCode != 200) {
        print('[ECCB] ERROR: POST failed with ${postResponse.statusCode}');
        return null;
      }

      final jsonData = jsonDecode(postResponse.body);
      final htmlContent = jsonData['html'] as String?;

      if (htmlContent == null || htmlContent.isEmpty) {
        print('[ECCB] ERROR: Missing html field in response');
        return null;
      }

      // Parse blocks in order; use the first one that contains EUR
      for (final blockMatch in _blockPattern.allMatches(htmlContent)) {
        final blockHtml = blockMatch.group(1)!;
        final rawRates = <String, double>{};

        for (final match in _itemPattern.allMatches(blockHtml)) {
          final countryName = match.group(1)!.trim();
          final valueStr = match.group(2)!.trim();
          final value = double.tryParse(valueStr);

          if (value == null) continue;

          final currency = _countryToCurrency[countryName];
          if (currency == null) {
            print('[ECCB] WARNING: Unknown country "$countryName"');
            continue;
          }

          rawRates[currency] = value;
        }

        if (rawRates.containsKey('EUR')) {
          print('[ECCB] Parsed ${rawRates.length} raw rates');
          rawRates['XCD'] = 1.0;
          final normalized = _normalizeToEurBase(rawRates);
          print('[ECCB] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }

      print('[ECCB] ERROR: No valid rates block found with EUR');
    } on TimeoutException catch (e) {
      print('[ECCB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[ECCB] ERROR: $e');
      print('[ECCB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'BBD', 'BZD', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR',
    'GBP', 'GYD', 'JMD', 'JPY', 'KRW', 'KWD', 'NOK', 'NZD', 'SEK',
    'TTD', 'USD', 'XCD',
  ];
}
class EestiPankProvider implements CurrencyProvider {
  @override
  String get id => 'eesti_pank';

  @override
  String get name => 'Eesti Pank';

  @override
  String get initials => 'EP';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[EP] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('haldus.eestipank.ee', '/en/export/currency_rates'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/csv,text/plain,*/*',
        },
      ).timeout(const Duration(seconds: 15));

      print('[EP] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final rawRates = <String, double>{};
        final lines = const LineSplitter().convert(response.body);

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          // Skip header lines
          if (trimmed.startsWith('"Euro related') ||
              trimmed.startsWith('"ECB rates at') ||
              trimmed.startsWith('"Currency Code"')) {
            continue;
          }

          final parts = trimmed.split(',');
          if (parts.length < 2) continue;

          final isoCode = parts[0].trim().replaceAll('"', '').toUpperCase();
          final rateStr = parts[1].trim().replaceAll('"', '');

          if (isoCode.isEmpty || rateStr.isEmpty) continue;

          final rate = double.tryParse(rateStr);
          if (rate == null || rate == 0) continue;

          rawRates[isoCode] = rate;
        }

        print('[EP] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['EUR'] = 1.0;

        print('[EP] Returning ${rawRates.length} rates (EUR-based)');
        return rawRates;
      }
      print('[EP] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[EP] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[EP] ERROR: $e');
      print('[EP] Stack: $st');
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
class FrbProvider implements CurrencyProvider {
  @override
  String get id => 'frb';

  @override
  String get name => 'Federal Reserve Board';

  @override
  String get initials => 'FRB';

  static const String _cbNamespace =
      'http://www.cbwiki.net/wiki/index.php/Specification_1.1';

  static final _usdPerPattern = RegExp(r'\(USD per ([A-Z]{3})\)');

  static const _coverageToIso = {
    'South Africa Rand': 'ZAR',
    'Brazil Real': 'BRL',
    'Canada Dollar': 'CAD',
    'China, P.R. Yuan': 'CNY',
    'Denmark Krone': 'DKK',
    'Hong Kong Dollar': 'HKD',
    'India Rupee': 'INR',
    'Japan Yen': 'JPY',
    'Malaysia Ringgit': 'MYR',
    'Mexico Peso': 'MXN',
    'Norway Krone': 'NOK',
    'Singapore Dollar': 'SGD',
    'South Korea Won': 'KRW',
    'Sri Lanka Rupee': 'LKR',
    'Sweden Krona': 'SEK',
    'Switzerland Franc': 'CHF',
    'Taiwan Dollar': 'TWD',
    'Thailand Baht': 'THB',
    'Venezuela Bolivar': 'VES',
  };

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[FRB] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('www.federalreserve.gov', '/feeds/data/H10_H10.XML'),
      ).timeout(const Duration(seconds: 15));

      print('[FRB] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final document = XmlDocument.parse(response.body);

        final rawRates = <String, double>{};
        final latestDates = <String, DateTime>{};

        for (final item in document.findAllElements('item')) {
          final stats = item
              .findElements('statistics', namespace: _cbNamespace)
              .firstOrNull;
          if (stats == null) continue;

          final otherStat = stats
              .findElements('otherStatistic', namespace: _cbNamespace)
              .firstOrNull;
          if (otherStat == null) continue;

          // Only process daily (business) data
          final obsPeriod = otherStat
              .findElements('observationPeriod', namespace: _cbNamespace)
              .firstOrNull;
          if (obsPeriod == null) continue;
          final frequency = obsPeriod.getAttribute('frequency');
          if (frequency != 'business') continue;

          // Parse observation date
          final dateStr = obsPeriod.innerText;
          final date = DateTime.tryParse(dateStr);
          if (date == null) continue;

          // Parse value
          final valueElem = otherStat
              .findElements('value', namespace: _cbNamespace)
              .firstOrNull;
          if (valueElem == null) continue;
          final valueStr = valueElem.innerText;
          if (valueStr == 'ND') continue;
          final value = double.tryParse(valueStr);
          if (value == null || value == 0) continue;

          // Parse coverage to identify currency
          final coverage = otherStat
              .findElements('coverage', namespace: _cbNamespace)
              .firstOrNull
              ?.innerText;
          if (coverage == null) continue;

          // Skip dollar indices
          if (coverage.contains('Index') || coverage.contains('index')) continue;

          // Extract ISO code
          String? isoCode;
          final usdPerMatch = _usdPerPattern.firstMatch(coverage);
          if (usdPerMatch != null) {
            isoCode = usdPerMatch.group(1);
          } else {
            isoCode = _coverageToIso[coverage];
          }
          if (isoCode == null) continue;

          // Keep only the latest rate for each currency
          final existingDate = latestDates[isoCode];
          if (existingDate == null || date.isAfter(existingDate)) {
            latestDates[isoCode] = date;

            // Coverage like "(USD per AUD)" means value is USD per unit of foreign
            // Other coverages mean value is foreign per USD
            if (usdPerMatch != null) {
              rawRates[isoCode] = value;
            } else {
              rawRates[isoCode] = 1.0 / value;
            }
          }
        }

        print('[FRB] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['USD'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[FRB] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[FRB] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[FRB] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[FRB] ERROR: $e');
      print('[FRB] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'HKD', 'INR',
    'JPY', 'KRW', 'LKR', 'MXN', 'MYR', 'NOK', 'NZD', 'SEK', 'SGD', 'THB',
    'TWD', 'USD', 'VES', 'ZAR',
  ];
}
class MefCambodiaProvider implements CurrencyProvider {
  @override
  String get id => 'mef_cambodia';

  @override
  String get name => 'Ministry of Economy and Finance (Cambodia)';

  @override
  String get initials => 'MEF';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[MEF] Starting fetchRates()');
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.https('data.mef.gov.kh', '/api/v1/realtime-api/exchange-rate'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      client.close();

      print('[MEF] Response status: ${response.statusCode}, body len: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final dataList = jsonData['data'];
        if (dataList is! List) {
          print('[MEF] ERROR: data is not a List');
          return null;
        }

        final rawRates = <String, double>{};

        for (final item in dataList) {
          if (item is! Map) continue;

          var isoCode = (item['currency_id'] as String?)?.trim().toUpperCase();
          final unit = item['unit'];
          final average = item['average'];

          if (isoCode == null || isoCode.isEmpty) continue;
          if (unit == null || average == null) continue;

          final unitVal = (unit is num) ? unit.toDouble() : double.tryParse(unit.toString());
          final avgVal = (average is num) ? average.toDouble() : double.tryParse(average.toString());

          if (unitVal == null || unitVal == 0 || avgVal == null || avgVal == 0) continue;

          // Map SDR to standard XDR
          if (isoCode == 'SDR') isoCode = 'XDR';

          // Rate is KHR per <unit> of foreign currency
          rawRates[isoCode] = avgVal / unitVal;
        }

        print('[MEF] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['KHR'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[MEF] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[MEF] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[MEF] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[MEF] ERROR: $e');
      print('[MEF] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'CAD', 'CHF', 'CNH', 'CNY', 'DKK', 'EUR', 'GBP', 'HKD',
    'IDR', 'INR', 'JPY', 'KHR', 'KRW', 'LAK', 'MMK', 'MYR', 'NGN', 'NZD',
    'PHP', 'SAR', 'SEK', 'SGD', 'THB', 'TWD', 'USD', 'VND', 'XDR', 'ZAR',
  ];
}
class NbeProvider implements CurrencyProvider {
  @override
  String get id => 'nbe';

  @override
  String get name => 'National Bank of Ethiopia';

  @override
  String get initials => 'NBE';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now().toUtc();
      for (int i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final dateStr =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

        final response = await http.get(
          Uri.https(
            'api.nbe.gov.et',
            '/api/filter-exchange-rates',
            {'date': dateStr},
          ),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode != 200) {
          print('[NBE] Date $dateStr: status=${response.statusCode}');
          continue;
        }

        final jsonData = jsonDecode(response.body);
        if (jsonData['success'] != true) {
          print('[NBE] Date $dateStr: success=false');
          continue;
        }

        final data = jsonData['data'];
        if (data is! List) {
          print('[NBE] Date $dateStr: no data array');
          continue;
        }

        final rawRates = <String, double>{};

        for (final item in data) {
          if (item is! Map) continue;

          final currency = item['currency'];
          if (currency is! Map) continue;

          final isoCode = currency['code'] as String?;
          final avgStr = item['weighted_average'] as String?;
          if (isoCode == null || avgStr == null) continue;

          final rate = double.tryParse(avgStr);
          if (rate == null || rate == 0) continue;

          rawRates[isoCode] = rate;
        }

        print('[NBE] Parsed ${rawRates.length} raw rates for $dateStr');
        if (rawRates.isNotEmpty) {
          rawRates['ETB'] = 1.0;
          final normalized = _normalizeToEurBase(rawRates);
          print('[NBE] Normalized rates count: ${normalized.length}');
          return normalized;
        }
      }
      print('[NBE] ERROR: No rates found in last 7 days');
    } catch (e, st) {
      print('[NBE] ERROR: $e');
      print('[NBE] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'CAD', 'CHF', 'CNY', 'DKK', 'DJF', 'ETB', 'EUR', 'GBP',
    'INR', 'JPY', 'KES', 'KWD', 'NOK', 'SAR', 'SEK', 'USD', 'XDR', 'ZAR',
  ];
}
class NbkrProvider implements CurrencyProvider {
  @override
  String get id => 'nbkr';

  @override
  String get name => 'National Bank of the Kyrgyz Republic';

  @override
  String get initials => 'NBKR';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBKR] Starting fetchRates()');
    try {
      final response = await http.get(
        Uri.https('nbkr.kg', '/XML/daily.xml'),
      ).timeout(const Duration(seconds: 15));

      print('[NBKR] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final rawRates = <String, double>{};
        final document = XmlDocument.parse(response.body);

        for (final currencyElem in document.findAllElements('Currency')) {
          final code = currencyElem.getAttribute('ISOCode');
          final valueStr = currencyElem.getElement('Value')?.innerText;
          if (code == null || valueStr == null || valueStr.isEmpty) continue;

          // NBKR uses comma as decimal separator
          final normalizedValueStr = valueStr.replaceAll(',', '.');
          final value = double.tryParse(normalizedValueStr);
          if (value == null || value == 0) continue;

          rawRates[code] = value;
        }

        print('[NBKR] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) {
          print('[NBKR] ERROR: rawRates is empty');
          return null;
        }

        // KGS itself
        rawRates['KGS'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBKR] Normalized rates count: ${normalized.length}');
        print('[NBKR] Normalized EUR: ${normalized['EUR']}');
        print('[NBKR] Normalized USD: ${normalized['USD']}');
        return normalized;
      }
      print('[NBKR] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBKR] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBKR] ERROR: $e');
      print('[NBKR] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'CNY', 'EUR', 'KGS', 'KZT', 'RUB', 'USD',
  ];
}
class NbtProvider implements CurrencyProvider {
  @override
  String get id => 'nbt';

  @override
  String get name => 'National Bank of Tajikistan';

  @override
  String get initials => 'NBT';

  @override
  Future<Map<String, double>?> fetchRates() async {
    print('[NBT] Starting fetchRates()');
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http.get(
        Uri.https(
          'nbt.tj',
          '/en/kurs/export_xml.php',
          {
            'date': dateStr,
            'export': 'xmlout',
          },
        ),
      ).timeout(const Duration(seconds: 15));

      print('[NBT] Response status: ${response.statusCode}, body len: ${response.body.length}');

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

          // Rate is TJS per <nominal> units of foreign currency
          rawRates[charCode] = value / nominal;
        }

        print('[NBT] Parsed ${rawRates.length} raw rates');
        if (rawRates.isEmpty) return null;

        rawRates['TJS'] = 1.0;

        final normalized = _normalizeToEurBase(rawRates);
        print('[NBT] Normalized rates count: ${normalized.length}');
        return normalized;
      }
      print('[NBT] ERROR: statusCode != 200');
    } on TimeoutException catch (e) {
      print('[NBT] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[NBT] ERROR: $e');
      print('[NBT] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'AMD', 'AUD', 'AZN', 'BYN', 'CAD', 'CHF', 'CNY', 'DKK',
    'EUR', 'GBP', 'GEL', 'INR', 'IRR', 'ISK', 'JPY', 'KGS', 'KRW', 'KWD',
    'KZT', 'MDL', 'MYR', 'NOK', 'PKR', 'PLN', 'SAR', 'SEK', 'SGD', 'THB',
    'TJS', 'TMT', 'TRY', 'UAH', 'USD',
  ];
}
class QcbProvider implements CurrencyProvider {
  @override
  String get id => 'qcb';

  @override
  String get name => 'Qatar Central Bank';

  @override
  String get initials => 'QCB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.https(
          'www.qcb.gov.qa',
          "/_api/web/lists/getbytitle('ExchangeRates')/items",
          {
            r'$top': '9',
            r'$orderby': 'ID desc',
          },
        ),
        headers: {'Accept': 'application/json;odata=verbose'},
      );

      if (response.statusCode != 200) {
        print('[QCB] Response status: ${response.statusCode}');
        return null;
      }

      final jsonData = jsonDecode(response.body);
      final results = jsonData['d']?['results'];
      if (results is! List) {
        print('[QCB] No results in response');
        return null;
      }

      final rawRates = <String, double>{};

      for (final item in results) {
        if (item is! Map) continue;

        var isoCode = item['CURR_CODE'] as String?;
        final rateVal = item['RATE_AMOUT'];
        if (isoCode == null || rateVal == null) continue;

        final rate = (rateVal is num)
            ? rateVal.toDouble()
            : double.tryParse(rateVal.toString());
        if (rate == null || rate == 0) continue;

        // Map offshore yuan to standard CNY
        if (isoCode == 'CNH') isoCode = 'CNY';

        rawRates[isoCode] = rate;
      }

      print('[QCB] Parsed ${rawRates.length} raw rates');
      if (rawRates.isEmpty) return null;

      rawRates['QAR'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[QCB] Normalized rates count: ${normalized.length}');
      return normalized;
    } catch (e, st) {
      print('[QCB] ERROR: $e');
      print('[QCB] Stack: $st');
      return null;
    }
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'HKD', 'JPY', 'QAR', 'USD',
  ];
}
class RbvProvider implements CurrencyProvider {
  @override
  String get id => 'rbv';

  @override
  String get name => 'Reserve Bank of Vanuatu';

  @override
  String get initials => 'RBV';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final client = _createPermissiveClient();
      final response = await client.get(
        Uri.parse(
          'https://www.rbv.gov.vu/index.php/en/exchange-rates/list/1?format=json&start=0&',
        ),
      );
      client.close();

      if (response.statusCode != 200) {
        print('[RBV] HTTP ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! List || body.isEmpty || body[0] is! List) {
        print('[RBV] Unexpected JSON structure');
        return null;
      }

      final entries = body[0] as List;
      if (entries.isEmpty || entries[0] is! Map) {
        print('[RBV] No entries found');
        return null;
      }

      final latest = entries[0] as Map<String, dynamic>;
      final rawRates = <String, double>{};

      final fieldMap = {
        'USD': 'exchange_rates___usd',
        'JPY': 'exchange_rates___jpy',
        'NZD': 'exchange_rates___nzd',
        'GBP': 'exchange_rates___GBP',
        'AUD': 'exchange_rates___aud',
        'EUR': 'exchange_rates___eur',
      };

      for (final entry in fieldMap.entries) {
        final value = latest[entry.value];
        if (value != null) {
          final rate = double.tryParse(value.toString());
          if (rate != null && rate != 0) {
            // Rates are "VUV per unit of foreign currency", invert to get
            // "foreign currency per 1 VUV"
            rawRates[entry.key] = 1.0 / rate;
          }
        }
      }

      print('[RBV] Parsed ${rawRates.length} raw rates');
      if (rawRates.isNotEmpty) {
        rawRates['VUV'] = 1.0;
        final normalized = _normalizeToEurBase(rawRates);
        print('[RBV] Normalized rates count: ${normalized.length}');
        return normalized;
      }
    } catch (e, st) {
      print('[RBV] ERROR: $e');
      print('[RBV] Stack: $st');
    }
    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'EUR', 'GBP', 'JPY', 'NZD', 'USD', 'VUV',
  ];
}
class RbzProvider implements CurrencyProvider {
  @override
  String get id => 'rbz';

  @override
  String get name => 'Reserve Bank of Zimbabwe';

  @override
  String get initials => 'RBZ';

  static final _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _pdfUrl(DateTime date) {
    final month = _monthNames[date.month];
    return 'https://www.rbz.co.zw/documents/Exchange_Rates/'
        '${date.year}/$month/RATES_${date.day}_${month.toUpperCase()}_${date.year}.pdf';
  }

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now().toUtc();
      // Try current date and up to 7 days back (skip weekends)
      for (int i = 0; i < 10; i++) {
        final date = now.subtract(Duration(days: i));
        final url = _pdfUrl(date);
        print('[RBZ] Trying $url');

        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          print('[RBZ] HTTP ${response.statusCode} for $url');
          continue;
        }

        final text = _extractPdfText(response.bodyBytes);
        if (text.isEmpty) {
          print('[RBZ] Empty text from PDF');
          continue;
        }

        final rates = parseRbzPdf(text);
        if (rates != null && rates.isNotEmpty) {
          print('[RBZ] Parsed ${rates.length} rates from ${date.toIso8601String()}');
          return rates;
        }
      }
    } catch (e, st) {
      print('[RBZ] ERROR: $e');
      print('[RBZ] Stack: $st');
    }
    return null;
  }

  /// Parses the flat text extracted from an RBZ PDF and returns
  /// EUR-normalized exchange rates.
  @visibleForTesting
  Map<String, double>? parseRbzPdf(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    // Find "INTERBANK RATE" to locate the start of data
    var startIdx = 0;
    for (var i = 0; i < words.length - 1; i++) {
      if (words[i] == 'INTERBANK' && words[i + 1] == 'RATE') {
        startIdx = i + 2;
        break;
      }
    }
    if (startIdx == 0) {
      print('[RBZ] Could not find INTERBANK RATE header');
      return null;
    }

    // Known date words to stop parsing
    final dateWords = {
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    };

    final rows = <String, List<double>>{};
    String? currentCurrency;
    final currentValues = <String>[];

    bool _looksLikeCurrency(String w) {
      if (w.length > 10) return false;
      if (dateWords.contains(w)) return false;
      // Currency codes: uppercase letters, possibly with /
      return RegExp(r'^[A-Z][A-Z/]+$').hasMatch(w);
    }

    bool _isNumeric(String w) {
      return RegExp(r'^[0-9.,]+$').hasMatch(w);
    }

    for (var i = startIdx; i < words.length; i++) {
      final w = words[i];
      if (dateWords.contains(w)) break;

      if (_looksLikeCurrency(w)) {
        if (currentCurrency != null && currentValues.length >= 3) {
          final nums = currentValues
              .where((v) => v != '*')
              .map((v) => double.tryParse(v.replaceAll(',', '')))
              .whereType<double>()
              .toList();
          if (nums.length >= 3) {
            rows[currentCurrency] = nums;
          }
        }
        currentCurrency = w;
        currentValues.clear();
      } else if (_isNumeric(w) || w == '*') {
        currentValues.add(w);
      }
    }

    // Save last row
    if (currentCurrency != null && currentValues.length >= 3) {
      final nums = currentValues
          .where((v) => v != '*')
          .map((v) => double.tryParse(v.replaceAll(',', '')))
          .whereType<double>()
          .toList();
      if (nums.length >= 3) {
        rows[currentCurrency] = nums;
      }
    }

    if (rows.isEmpty || !rows.containsKey('USD')) {
      print('[RBZ] No data rows or missing USD');
      return null;
    }

    // USD row: indices are 1 1 1.0000, ZWG rates are the 4th-6th values
    final usdValues = rows['USD']!;
    final usdZwgRate = usdValues.length >= 6 ? usdValues[5] : usdValues.last;
    if (usdZwgRate == 0) {
      print('[RBZ] USD ZWG rate is zero');
      return null;
    }

    final rawRates = <String, double>{};

    for (final entry in rows.entries) {
      var currency = entry.key;
      final values = entry.value;

      // Skip defunct/unnecessary currencies
      if (currency == 'XAU' || currency == 'SDR' || currency == 'CYP') continue;

      // Normalise combined currency labels
      if (currency == 'ZMW/ZMK') currency = 'ZMW';
      if (currency == 'MZN/MET') currency = 'MZN';

      // Need both index mid (values[2]) and rate mid (values[5])
      if (values.length < 6) continue;

      final indexMid = values[2];
      final rateMid = values[5];
      if (indexMid == 0 || rateMid == 0) continue;

      double zwgPerForeign;
      if (currency == 'USD') {
        zwgPerForeign = usdZwgRate;
      } else {
        // The RBZ tables mix two conventions:
        //   A) index = USD per foreign, rate = ZWG per foreign
        //      => rate ≈ index * usdZwgRate
        //   B) index = foreign per USD, rate = foreign per ZWG
        //      => rate ≈ index / usdZwgRate
        final matchA = (rateMid - (indexMid * usdZwgRate)).abs();
        final matchB = (rateMid - (indexMid / usdZwgRate)).abs();
        if (matchA < matchB) {
          // Convention A: rate is already ZWG per foreign unit
          zwgPerForeign = rateMid;
        } else {
          // Convention B: rate is foreign per ZWG, invert it
          zwgPerForeign = 1.0 / rateMid;
        }
      }

      if (zwgPerForeign > 0) {
        // Store as foreign per ZWG (i.e. 1 ZWG = X foreign)
        rawRates[currency] = 1.0 / zwgPerForeign;
      }
    }

    print('[RBZ] Raw rates count: ${rawRates.length}');
    if (rawRates.isNotEmpty) {
      rawRates['ZWG'] = 1.0;
      final normalized = _normalizeToEurBase(rawRates);
      print('[RBZ] Normalized rates count: ${normalized.length}');
      return normalized;
    }

    return null;
  }

  @override
  List<String> get supportedCurrencies => [
    'AFN', 'ARS', 'AUD', 'BWP', 'BRL', 'CAD', 'CHF', 'CNY',
    'DKK', 'EGP', 'ETB', 'EUR', 'GBP', 'HKD', 'INR', 'JPY',
    'KES', 'LSL', 'MWK', 'MUR', 'MYR', 'MZN', 'NOK', 'NZD',
    'RUB', 'SEK', 'SZL', 'THB', 'TZS', 'USD', 'XAF', 'ZAR',
    'ZMW', 'ZWG',
  ];
}
class SamaProvider implements CurrencyProvider {
  @override
  String get id => 'sama';

  @override
  String get name => 'Saudi Arabian Monetary Authority';

  @override
  String get initials => 'SAMA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      for (var i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr =
            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

        final response = await http.get(
          Uri.https(
            'www.sama.gov.sa',
            '/ar-sa/_LAYOUTS/15/SAMA.Portal/PortalHandler.ashx',
            {
              'op': 'filterCurrenciesWithCount',
              'isArabic': 'false',
              'code': '',
              'date': dateStr,
              'limit': '100',
            },
          ),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) {
          print('[SAMA] HTTP ${response.statusCode} for $dateStr');
          continue;
        }

        final result = parseSamaJson(response.body);
        if (result != null) {
          print('[SAMA] Found valid data for $dateStr');
          return result;
        }
      }
      print('[SAMA] ERROR: No valid data found in the last 7 days');
    } catch (e, st) {
      print('[SAMA] ERROR: $e');
      print('[SAMA] Stack: $st');
    }
    return null;
  }

  /// Parses the SAMA JSON response and returns EUR-normalized rates.
  @visibleForTesting
  Map<String, double>? parseSamaJson(String jsonText) {
    final jsonData = jsonDecode(jsonText);
    final data = jsonData['data'];
    if (data is! List) {
      print('[SAMA] No data in response');
      return null;
    }

    final rawRates = <String, double>{};

    for (final item in data) {
      if (item is! Map) continue;

      var currencyCode = item['CurrencyCode'] as String?;
      final rateVal = item['CurrencyRate'];
      if (currencyCode == null || rateVal == null) continue;

      // Strip trailing '=' if present
      if (currencyCode.endsWith('=')) {
        currencyCode = currencyCode.substring(0, currencyCode.length - 1);
      }

      final rate = (rateVal is num)
          ? rateVal.toDouble()
          : double.tryParse(rateVal.toString());
      if (rate == null || rate <= 0) continue;

      // Skip defunct / non-currency entries
      if (currencyCode == 'CYP' ||
          currencyCode == 'MTL' ||
          currencyCode == 'SKK' ||
          currencyCode == 'SDR') continue;

      rawRates[currencyCode] = rate;
    }

    print('[SAMA] Parsed ${rawRates.length} raw rates');
    if (rawRates.isEmpty) return null;

    rawRates['SAR'] = 1.0;
    final normalized = _normalizeToEurBase(rawRates);
    print('[SAMA] Normalized rates count: ${normalized.length}');
    return normalized;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AFN', 'ALL', 'AUD', 'BAM', 'BDT', 'BGN', 'BHD', 'BND', 'BRL',
    'CAD', 'CHF', 'CNY', 'CUP', 'CZK', 'DKK', 'DZD', 'EGP', 'ETB', 'EUR',
    'GBP', 'HKD', 'HUF', 'IDR', 'INR', 'ISK', 'JOD', 'JPY', 'KES', 'KRW',
    'KWD', 'LBP', 'LKR', 'LYD', 'MAD', 'MGA', 'MMK', 'MUR', 'MXN', 'MYR',
    'NGN', 'NOK', 'NZD', 'OMR', 'PHP', 'PKR', 'PLN', 'QAR', 'RON', 'RUB',
    'SEK', 'SGD', 'SAR', 'THB', 'TJS', 'TND', 'TRY', 'TWD', 'TZS', 'UGX',
    'USD', 'VND', 'XAF', 'XOF', 'YER', 'ZAR',
  ];
}
final List<CurrencyProvider> currencyProviders = [
  InforEuroProvider(),
  EcbProvider(),
  // Alphabetically by country
  BcraProvider(),                    // Argentina
  BoaProvider(),                     // Albania
  CbaProvider(),                     // Armenia
  RbaProvider(),                     // Australia
  CbarProvider(),                    // Azerbaijan
  BangladeshBankProvider(),          // Bangladesh
  CbbBarbadosProvider(),             // Barbados
  CbbProvider(),                     // Bahrain
  BermudaCustomsProvider(),          // Bermuda
  BcbProvider(),                     // Bolivia
  BcchProvider(),                    // Chile
  CbbhProvider(),                    // Bosnia and Herzegovina
  BnbProvider(),                     // Bulgaria
  BrbProvider(),                     // Burundi
  BankOfCanadaProvider(),            // Canada
  BcvProvider(),                     // Cape Verde
  MefCambodiaProvider(),             // Cambodia
  HnbProvider(),                     // Croatia
  BccCongoProvider(),                // Congo
  BccProvider(),                     // Cuba
  CnbProvider(),                     // Czech Republic
  DanmarksNationalbankProvider(),    // Denmark
  EccbProvider(),                    // Eastern Caribbean
  EestiPankProvider(),               // Estonia
  NbeProvider(),                     // Ethiopia
  BankOfFinlandProvider(),           // Finland
  NbgProvider(),                     // Georgia
  BogProvider(),                     // Guyana
  HkmaProvider(),                    // Hong Kong
  MnbProvider(),                     // Hungary
  CentralBankOfIcelandProvider(),    // Iceland
  BiIndonesiaProvider(),             // Indonesia
  BoiProvider(),                     // Israel
  BancaDItaliaProvider(),            // Italy
  BojProvider(),                     // Japan
  NbrkProvider(),                    // Kazakhstan
  CbkProvider(),                     // Kenya
  BokProvider(),                     // Korea
  NbkrProvider(),                    // Kyrgyz Republic
  BankOfLatviaProvider(),            // Latvia
  BankOfLithuaniaProvider(),         // Lithuania
  BankNegaraMalaysiaProvider(),      // Malaysia
  BnmProvider(),                     // Moldova
  CbcgProvider(),                    // Montenegro
  BomProvider(),                     // Mongolia
  CbmProvider(),                     // Myanmar
  NrbProvider(),                     // Nepal
  BcnProvider(),                     // Nicaragua
  CbnProvider(),                     // Nigeria
  NbrmProvider(),                    // North Macedonia
  KktcmbProvider(),                  // Northern Cyprus
  NorgesBankProvider(),              // Norway
  SbpProvider(),                     // Pakistan
  BspProvider(),                     // Papua New Guinea
  BcpProvider(),                     // Paraguay
  BankOfAlgeriaProvider(),           // Algeria
  BcrpProvider(),                    // Peru
  BangkoSentralProvider(),           // Philippines
  NbpProvider(),                     // Poland
  BpstatProvider(),                  // Portugal
  QcbProvider(),                     // Qatar
  BnrProvider(),                     // Romania
  BankRossiiProvider(),              // Russia
  SamaProvider(),                    // Saudi Arabia
  CbsProvider(),                     // Seychelles
  CbsiProvider(),                    // Solomon Islands
  CbvsProvider(),                    // Suriname
  BslProvider(),                     // Sierra Leone
  MasProvider(),                     // Singapore
  NbsProvider(),                     // Slovakia
  BsiProvider(),                     // Slovenia
  RiksbankProvider(),                // Sweden
  CbcTaiwanProvider(),               // Taiwan
  NbtProvider(),                     // Tajikistan
  BotProvider(),                     // Thailand
  CbpmrProvider(),                   // Transnistria
  CbttProvider(),                    // Trinidad and Tobago
  TcmbProvider(),                    // Türkiye
  NbuProvider(),                     // Ukraine
  BcuProvider(),                     // Uruguay
  NrbtProvider(),                    // Tonga
  RbfProvider(),                     // Fiji
  RbnzProvider(),                    // New Zealand
  FrbProvider(),                     // USA
  CbuProvider(),                     // Uzbekistan
  RbvProvider(),                     // Vanuatu
  BcvVenezuelaProvider(),            // Venezuela
  BceaoProvider(),                   // West African States
  BozProvider(),                     // Zambia
  RbzProvider(),                     // Zimbabwe
];

class BozProvider implements CurrencyProvider {
  @override
  String get id => 'boz';

  @override
  String get name => 'Bank of Zambia';

  @override
  String get initials => 'BoZ';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://www.boz.zm/jsonapi/node/exchange_rates?sort=-field_average_exchange_rate_date&page[limit]=1&include=field_average_exchange_rates',
        ),
        headers: {'Accept': 'application/vnd.api+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseBozJson(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['ZMW'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBozJson(String jsonText) {
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>?;
    final included = decoded['included'] as List<dynamic>?;
    if (data == null || data.isEmpty || included == null) return null;

    final node = data[0] as Map<String, dynamic>;
    final relationships = node['relationships'] as Map<String, dynamic>?;
    final fieldRates = relationships?['field_average_exchange_rates']
        as Map<String, dynamic>?;
    final rateRefs = fieldRates?['data'] as List<dynamic>?;
    if (rateRefs == null || rateRefs.isEmpty) return null;

    final rateIds = rateRefs
        .map((r) => (r as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .toSet();

    final rawRates = <String, double>{};
    for (final item in included) {
      final itemMap = item as Map<String, dynamic>;
      if (!rateIds.contains(itemMap['id'])) continue;

      final attrs = itemMap['attributes'] as Map<String, dynamic>?;
      if (attrs == null) continue;

      final currency = attrs['currency'] as String?;
      final buyingStr = attrs['buying'] as String?;
      final sellingStr = attrs['selling'] as String?;
      if (currency == null || buyingStr == null || sellingStr == null) {
        continue;
      }

      final buying = double.tryParse(buyingStr);
      final selling = double.tryParse(sellingStr);
      if (buying == null || selling == null || buying == 0 || selling == 0) {
        continue;
      }

      rawRates[currency] = (buying + selling) / 2.0;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'EUR', 'GBP', 'USD', 'ZAR', 'ZMW',
  ];
}

class KktcmbProvider implements CurrencyProvider {
  @override
  String get id => 'kktcmb';

  @override
  String get name => 'Central Bank of the Turkish Republic of Northern Cyprus';

  @override
  String get initials => 'KKTCMB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://mb.gov.ct.tr/kur/gunluk.xml'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      return parseKktcmbXml(response.body);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseKktcmbXml(String xml) {
    final rawRates = <String, double>{};

    try {
      final document = XmlDocument.parse(xml);

      for (final resmiKur in document.findAllElements('Resmi_Kur')) {
        final sembol = resmiKur.findElements('Sembol').firstOrNull?.innerText;
        final birimStr = resmiKur.findElements('Birim').firstOrNull?.innerText;
        final dovizAlis = resmiKur.findElements('Doviz_Alis').firstOrNull?.innerText;

        if (sembol == null || dovizAlis == null) continue;

        final birim = int.tryParse(birimStr ?? '1') ?? 1;
        if (birim == 0) continue;

        final rate = double.tryParse(dovizAlis);
        if (rate == null || rate == 0) continue;

        rawRates[sembol] = rate / birim;
      }
    } catch (_) {
      return null;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) return null;

    rawRates['TRY'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'DKK', 'EUR', 'GBP', 'JPY', 'KWD', 'NOK', 'SAR',
    'SEK', 'TRY', 'USD',
  ];
}

class BangkoSentralProvider implements CurrencyProvider {
  @override
  String get id => 'bangko_sentral';

  @override
  String get name => 'Bangko Sentral ng Pilipinas';

  @override
  String get initials => 'BSP';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse(
          "https://www.bsp.gov.ph/_api/web/lists/getByTitle('Exchange%20Rate')/items?\$select=*&\$filter=Group%20eq%20'1'&\$orderby=Ordering%20asc",
        ),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      return parseBangkoSentralXml(response.body);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBangkoSentralXml(String xmlText) {
    final exchangeRates = <String, double>{};

    try {
      final document = XmlDocument.parse(xmlText);

      for (final entry in document.findAllElements('entry')) {
        final symbol = entry.findAllElements('d:Symbol').firstOrNull?.innerText;
        final eurEquivalent = entry.findAllElements('d:EURequivalent').firstOrNull?.innerText;

        if (symbol == null || eurEquivalent == null) continue;
        if (eurEquivalent == 'N/A') continue;

        final rate = double.tryParse(eurEquivalent);
        if (rate == null || rate == 0) continue;

        exchangeRates[symbol] = rate;
      }
    } catch (_) {
      return null;
    }

    if (exchangeRates.isEmpty || !exchangeRates.containsKey('EUR')) return null;

    exchangeRates['EUR'] = 1.0;
    exchangeRates['PHP'] = 1.0;
    return exchangeRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'ARS', 'AUD', 'BHD', 'BND', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK',
    'EUR', 'GBP', 'HKD', 'IDR', 'INR', 'JPY', 'KRW', 'KWD', 'MXN', 'MYR',
    'NOK', 'NZD', 'PKR', 'PHP', 'SAR', 'SEK', 'SGD', 'SYP', 'THB', 'TWD',
    'USD', 'VES', 'ZAR',
  ];
}

class BcchProvider implements CurrencyProvider {
  @override
  String get id => 'bcch';

  @override
  String get name => 'Bank of Chile';

  @override
  String get initials => 'BCCh';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      // The daily indicators page contains a link to the exchange-rates list.
      final indicatorsResponse = await http
          .get(Uri.parse(
              'https://si3.bcentral.cl/Indicadoressiete/secure/Indicadoresdiarios.aspx?Idioma=en-US'))
          .timeout(const Duration(seconds: 15));

      if (indicatorsResponse.statusCode != 200) return null;

      // Extract the first ListaSerie.aspx link (Foreign currencies-dollar parity)
      final listaMatch = RegExp(
        r'href="(ListaSerie\.aspx\?param=[^"]+)"',
        caseSensitive: false,
      ).firstMatch(indicatorsResponse.body);

      if (listaMatch == null) return null;

      final listaUrl =
          'https://si3.bcentral.cl/Indicadoressiete/secure/${listaMatch.group(1)!}';
      final response = await http
          .get(Uri.parse(listaUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseBcchHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['CLP'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBcchHtml(String html) {
    final tableStart = html.indexOf('id="tbl_lista_series"');
    if (tableStart == -1) return null;

    final tableEnd = html.indexOf('</table>', tableStart);
    if (tableEnd == -1) return null;

    final tableHtml = html.substring(tableStart, tableEnd + 8);
    final rawRates = <String, double>{};

    final rowRegex = RegExp(
      r'<td[^>]*>\s*([^<]+?)\s*</td>\s*<td[^>]*>\s*([0-9.,]+)\s*</td>\s*<td[^>]*>\s*<a[^>]*gcode=([A-Z]{3})_([A-Z]{3})',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(tableHtml)) {
      final rateStr = match.group(2)!.replaceAll(',', '');
      final rate = double.tryParse(rateStr);
      if (rate == null || rate == 0) continue;

      final gcodePrefix = match.group(3)!.toUpperCase();
      var isoCode = match.group(4)!.toUpperCase();

      // Only process TCN (nominal exchange rate) rows
      if (gcodePrefix != 'TCN') continue;

      // Skip obsolete currencies
      if (isoCode == 'VEB') continue;

      // Map non-standard codes
      const codeMap = <String, String>{
        'BOL': 'BOB',
        'DEG': 'XDR',
        'BSP': 'BSD',
        'RUR': 'RUB',
      };
      isoCode = codeMap[isoCode] ?? isoCode;

      rawRates[isoCode] = rate;
      // Panamanian Balboa is pegged 1:1 to USD
      if (isoCode == 'PAB') {
        rawRates['USD'] = rate;
      }
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BOB', 'BSD', 'CAD', 'CHF', 'CLP', 'CNY', 'COP',
    'EUR', 'GBP', 'JPY', 'MXN', 'PAB', 'RUB', 'THB', 'USD',
    'UYU', 'XDR',
  ];
}

class BspProvider implements CurrencyProvider {
  @override
  String get id => 'bsp';

  @override
  String get name => 'Bank of Papua New Guinea';

  @override
  String get initials => 'BSP';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://www.bsp.com.pg/international-services/foreign-exchange/exchange-rates/'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseBspHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['PGK'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  static String? _extractFirstJsonObject(String html, int startIdx) {
    var braceDepth = 0;
    var inString = false;
    var escapeNext = false;
    var jsonStart = -1;

    for (var i = startIdx; i < html.length; i++) {
      final ch = html[i];
      if (escapeNext) {
        escapeNext = false;
        continue;
      }
      if (ch == '\\') {
        escapeNext = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (ch == '{') {
        if (braceDepth == 0) {
          jsonStart = i;
        }
        braceDepth++;
      } else if (ch == '}') {
        braceDepth--;
        if (braceDepth == 0 && jsonStart != -1) {
          return html.substring(jsonStart, i + 1);
        }
      }
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseBspHtml(String html) {
    final startIdx = html.indexOf('CBSimpleExchangeRateCalculator');
    if (startIdx == -1) return null;
    final parenIdx = html.indexOf('(', startIdx);
    if (parenIdx == -1) return null;

    final jsonStr = _extractFirstJsonObject(html, parenIdx + 1);
    if (jsonStr == null || !jsonStr.contains('"buy_tt"')) return null;

    final rawRates = <String, double>{};

    // Parse individual currency objects from the JSON-like structure
    final entryRegex = RegExp(
      r'"([A-Z]{3})":\s*\{[^}]*"buy_tt"\s*:\s*"([0-9.]*)"',
      caseSensitive: false,
    );

    for (final match in entryRegex.allMatches(jsonStr)) {
      final code = match.group(1)!.toUpperCase();
      final buyTtStr = match.group(2)!;
      final buyTt = double.tryParse(buyTtStr);
      if (buyTt == null || buyTt == 0) continue;

      // Invert: rate is foreign-per-PGK, we want PGK-per-foreign
      rawRates[code] = 1.0 / buyTt;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'FJD', 'GBP', 'HKD',
    'INR', 'JPY', 'NZD', 'PGK', 'PHP', 'SBD', 'SGD', 'THB',
    'TOP', 'USD', 'VUV', 'WST', 'ZAR',
  ];
}

class CbsiProvider implements CurrencyProvider {
  @override
  String get id => 'cbsi';

  @override
  String get name => 'Central Bank of Solomon Islands';

  @override
  String get initials => 'CBSI';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.cbsi.com.sb/statistics/exchange-rates/'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseCbsiHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['SBD'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseCbsiHtml(String html) {
    final tableStart = html.indexOf('id="tablepress-2"');
    if (tableStart == -1) return null;

    final tableEnd = html.indexOf('</table>', tableStart);
    if (tableEnd == -1) return null;

    final tableHtml = html.substring(tableStart, tableEnd + 8);
    final rawRates = <String, double>{};

    final rowRegex = RegExp(
      r'<td[^>]*>\s*(?:<img[^>]*>)?\s*([A-Z]{3})\s*</td>\s*<td[^>]*>\s*([0-9.]+)\s*</td>',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(tableHtml)) {
      final code = match.group(1)!.toUpperCase();
      final rateStr = match.group(2)!;
      final rate = double.tryParse(rateStr);
      if (rate == null || rate == 0) continue;

      // Skip SDR and Index rows
      if (code == 'SDR' || code == 'Index') continue;

      // Invert: rate is foreign-per-SBD, we want SBD-per-foreign
      rawRates[code] = 1.0 / rate;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CNY', 'EUR', 'GBP', 'JPY', 'NZD', 'SBD', 'USD',
  ];
}

class CbttProvider implements CurrencyProvider {
  @override
  String get id => 'cbtt';

  @override
  String get name => 'Central Bank of Trinidad and Tobago';

  @override
  String get initials => 'CBTT';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final body = <String, String>{};
      body['draw'] = '1';

      final columnNames = [
        'Date',
        'BBD Buying Rate', 'BBD Selling Rate',
        'CAD Buying Rate', 'CAD Selling Rate',
        'CHF Buying Rate', 'CHF Selling Rate',
        'XCD Buying Rate', 'XCD Selling Rate',
        'GBP Buying Rate', 'GBP Selling Rate',
        'GYD Buying Rate', 'GYD Selling Rate',
        'JMD Buying Rate', 'JMD Selling Rate',
        'JPY Buying Rate', 'JPY Selling Rate',
        'USD Buying Rate', 'USD Selling Rate',
        'EUR Buying Rate', 'EUR Selling Rate',
      ];

      for (var i = 0; i < columnNames.length; i++) {
        body['columns[$i][data]'] = '$i';
        body['columns[$i][name]'] = columnNames[i];
        body['columns[$i][searchable]'] = 'true';
        body['columns[$i][orderable]'] = i == 0 ? 'true' : 'false';
        body['columns[$i][search][value]'] = '';
        body['columns[$i][search][regex]'] = 'false';
      }

      body['order[0][column]'] = '0';
      body['order[0][dir]'] = 'desc';
      body['start'] = '0';
      body['length'] = '1';
      body['search[value]'] = '';
      body['search[regex]'] = 'false';
      body['wdtNonce'] = '34d3e9a3ea';
      body['sRangeSeparator'] = '|';

      final response = await http.post(
        Uri.parse(
          'https://www.central-bank.org.tt/quo-backend/admin-ajax.php?action=get_wdtable&table_id=106',
        ),
        body: body,
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final rawRates = parseCbttJson(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['TTD'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseCbttJson(String jsonText) {
    final jsonData = jsonDecode(jsonText);
    final data = jsonData['data'];
    if (data is! List || data.isEmpty) return null;

    final row = data.first;
    if (row is! List || row.length < 21) return null;

    final rawRates = <String, double>{};

    // Buying rates are at odd indices
    final currencyMap = <int, String>{
      1: 'BBD',
      3: 'CAD',
      5: 'CHF',
      7: 'XCD',
      9: 'GBP',
      11: 'GYD',
      13: 'JMD',
      15: 'JPY',
      17: 'USD',
      19: 'EUR',
    };

    for (final entry in currencyMap.entries) {
      final valueStr = row[entry.key]?.toString();
      if (valueStr == null || valueStr.isEmpty) continue;
      final rate = double.tryParse(valueStr);
      if (rate == null || rate == 0) continue;
      rawRates[entry.value] = rate;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'BBD', 'CAD', 'CHF', 'EUR', 'GBP', 'GYD', 'JMD', 'JPY', 'TTD', 'USD',
    'XCD',
  ];
}

class NrbtProvider implements CurrencyProvider {
  @override
  String get id => 'nrbt';

  @override
  String get name => 'National Reserve Bank of Tonga';

  @override
  String get initials => 'NRBT';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://www.reservebank.to/index.php/financial-system/financial-markets/exchange-rates'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final rawRates = parseNrbtHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['TOP'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseNrbtHtml(String html) {
    final tableStart = html.indexOf('class="table-custom-4c"');
    if (tableStart == -1) return null;

    final tableEnd = html.indexOf('</table>', tableStart);
    if (tableEnd == -1) return null;

    final tableHtml = html.substring(tableStart, tableEnd + 8);
    final rawRates = <String, double>{};

    final nameToCode = <String, String>{
      'Australian Dollar': 'AUD',
      'European Euro': 'EUR',
      'Fijian Dollar': 'FJD',
      'British Pound': 'GBP',
      'Japanese Yen': 'JPY',
      'New Zealand Dollar': 'NZD',
      'United States Dollar': 'USD',
      'Samoan Tala': 'WST',
      'Switzerland Francs': 'CHF',
      'Canada Dollar': 'CAD',
      'Sweden Kronor': 'SEK',
      'Singapore Dollar': 'SGD',
    };

    final rowRegex = RegExp(
      r'<td[^>]*>([^<]+)</td>\s*<td[^>]*>([0-9.]+)</td>\s*<td[^>]*>([0-9.]+)</td>\s*<td[^>]*>([0-9.]+)</td>',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(tableHtml)) {
      final name = match.group(1)!.trim();
      final midStr = match.group(3)!;
      final mid = double.tryParse(midStr);
      if (mid == null || mid == 0) continue;

      final code = nameToCode[name];
      if (code == null) continue;

      // Invert: rate is foreign-per-TOP, we want TOP-per-foreign
      rawRates[code] = 1.0 / mid;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CAD', 'CHF', 'EUR', 'FJD', 'GBP', 'JPY', 'NZD',
    'SEK', 'SGD', 'TOP', 'USD', 'WST',
  ];
}

class RbfProvider implements CurrencyProvider {
  @override
  String get id => 'rbf';

  @override
  String get name => 'Reserve Bank of Fiji';

  @override
  String get initials => 'RBF';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(Uri.parse('https://www.rbf.gov.fj/'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return null;

      final rawRates = parseRbfHtml(response.body);
      if (rawRates == null || rawRates.isEmpty) return null;

      rawRates['FJD'] = 1.0;
      return _normalizeToEurBase(rawRates);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseRbfHtml(String html) {
    final rawRates = <String, double>{};

    final itemRegex = RegExp(
      r'<div class="list_item lists_2 clearfix">.*?<h4>([^<]+)</h4>\s*<div class="desc">([0-9.]+)</div>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in itemRegex.allMatches(html)) {
      var code = match.group(1)!.trim().toUpperCase();
      final rateStr = match.group(2)!;
      final rate = double.tryParse(rateStr);
      if (rate == null || rate == 0) continue;

      // Map EURO to EUR
      if (code == 'EURO') code = 'EUR';

      // Invert: rate is foreign-per-FJD, we want FJD-per-foreign
      rawRates[code] = 1.0 / rate;
    }

    if (rawRates.isEmpty) return null;
    return rawRates;
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'EUR', 'FJD', 'GBP', 'JPY', 'NZD', 'USD',
  ];
}

class RbnzProvider implements CurrencyProvider {
  @override
  String get id => 'rbnz';

  @override
  String get name => 'Reserve Bank of New Zealand';

  @override
  String get initials => 'RBNZ';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://www.rbnz.govt.nz/statistics/series/exchange-and-interest-rates/exchange-rates-and-the-trade-weighted-index'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      return parseRbnzHtml(response.body);
    } on TimeoutException catch (_) {
      return null;
    } catch (e) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseRbnzHtml(String html) {
    final tableStart = html.indexOf('class="table--data"');
    if (tableStart == -1) return null;

    final tableEnd = html.indexOf('</table>', tableStart);
    if (tableEnd == -1) return null;

    final tableHtml = html.substring(tableStart, tableEnd + 8);
    final rawRates = <String, double>{};

    final nameToCode = <String, String>{
      'United States dollar': 'USD',
      'UK pound sterling': 'GBP',
      'Australian dollar': 'AUD',
      'Japanese yen': 'JPY',
      'European euro': 'EUR',
      'Chinese renminbi': 'CNY',
    };

    // Extract rows with currency names and rates
    final rowRegex = RegExp(
      r'<td>([^<]+)</td>\s*<td>[0-9.]+</td>\s*<td[^>]*class="table__cell--bold"[^>]*>([0-9.]+)</td>',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(tableHtml)) {
      final name = match.group(1)!.trim();
      final rateStr = match.group(2)!;
      final rate = double.tryParse(rateStr);
      if (rate == null || rate == 0) continue;

      final code = nameToCode[name];
      if (code == null) continue;

      // Invert: rate is foreign-per-NZD, we want NZD-per-foreign
      rawRates[code] = 1.0 / rate;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) return null;

    rawRates['NZD'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'CNY', 'EUR', 'GBP', 'JPY', 'NZD', 'USD',
  ];
}

class SbpProvider implements CurrencyProvider {
  @override
  String get id => 'sbp';

  @override
  String get name => 'State Bank of Pakistan';

  @override
  String get initials => 'SBP';

  static const _monthAbbrs = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final now = DateTime.now();
      for (var i = 0; i < 7; i++) {
        final date = now.subtract(Duration(days: i));
        final yyyy = date.year;
        final mon = _monthAbbrs[date.month];
        final dd = date.day.toString().padLeft(2, '0');
        final yy = (date.year % 100).toString().padLeft(2, '0');
        final url =
            'https://www.sbp.org.pk/ecodata/rates/war/$yyyy/$mon/$dd-$mon-$yy.pdf';

        print('[SBP] Trying $url');
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200 &&
            response.bodyBytes.length > 4 &&
            String.fromCharCodes(response.bodyBytes.sublist(0, 4)) == '%PDF') {
          print('[SBP] Got PDF for ${date.toIso8601String().split('T').first}');
          final text = _extractPdfText(response.bodyBytes);
          final result = parseSbpPdfText(text);
          print('[SBP] Parsed result: ${result != null ? '${result.length} rates' : 'null'}');
          return result;
        }
      }
      print('[SBP] No PDF found in the last 7 days');
    } on TimeoutException catch (e) {
      print('[SBP] ERROR: Timeout - $e');
    } catch (e, st) {
      print('[SBP] ERROR: $e');
      print('[SBP] Stack: $st');
    }
    return null;
  }

  @visibleForTesting
  static Map<String, double>? parseSbpPdfText(String text) {
    final rawRates = <String, double>{};

    // Match: CURRENCY buying selling
    // e.g. "USD 278.5150 278.9401"
    final lineRegex = RegExp(
      r'([A-Z]{3})\s+([0-9.]+)\s+([0-9.]+)',
      caseSensitive: false,
    );

    for (final match in lineRegex.allMatches(text)) {
      final code = match.group(1)!.toUpperCase();
      final buying = double.tryParse(match.group(2)!);
      final selling = double.tryParse(match.group(3)!);
      if (buying == null || selling == null || buying == 0) continue;

      final mid = (buying + selling) / 2.0;
      rawRates[code] = mid;
    }

    if (rawRates.isEmpty || !rawRates.containsKey('EUR')) {
      return null;
    }

    rawRates['PKR'] = 1.0;
    final normalized = _normalizeToEurBase(rawRates);
    return normalized;
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'AUD', 'CAD', 'CHF', 'CNY', 'EUR', 'GBP', 'JPY',
    'PKR', 'SAR', 'USD',
  ];
}

class BankOfAlgeriaProvider implements CurrencyProvider {
  @override
  String get id => 'bank_of_algeria';

  @override
  String get name => 'Bank of Algeria';

  @override
  String get initials => 'BoA';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.bank-of-algeria.dz/taux-de-change-journalier/'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return parseBankOfAlgeriaHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBankOfAlgeriaHtml(String html) {
    // Extract the first table (most recent date, contains currency codes)
    final firstTableEnd = html.indexOf('</tbody></table>');
    if (firstTableEnd == -1) return null;

    final tableStart = html.lastIndexOf('<table', firstTableEnd);
    if (tableStart == -1) return null;

    final tableHtml = html.substring(tableStart, firstTableEnd);

    final rawRates = <String, double>{};
    final regex = RegExp(
      r'<td>([^<]+)</td>\s*<td>([0-9.]+)</td>',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(tableHtml)) {
      var currency = match.group(1)!.trim().toUpperCase();
      final rateStr = match.group(2)!.trim();
      final rate = double.tryParse(rateStr);
      if (rate == null || rate <= 0) continue;

      // Map SDR (French abbreviation) to ISO XDR
      if (currency == 'SDR') currency = 'XDR';

      rawRates[currency] = rate;
    }

    if (!rawRates.containsKey('EUR')) return null;

    // Rates are quoted as DZD per unit of foreign currency,
    // so DZD is the implicit base currency (1 DZD = 1 DZD).
    rawRates['DZD'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AED', 'CAD', 'CHF', 'CNY', 'DKK', 'DZD', 'EUR', 'GBP', 'JPY', 'KWD',
    'LYD', 'MAD', 'MRU', 'NOK', 'SAR', 'SEK', 'TND', 'USD', 'XDR',
  ];
}

class CbbBarbadosProvider implements CurrencyProvider {
  @override
  String get id => 'cbb_barbados';

  @override
  String get name => 'Central Bank of Barbados';

  @override
  String get initials => 'CBB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    final client = http.Client();
    try {
      // Step 1: GET the page to establish a session and extract CSRF token
      final pageResponse = await client
          .get(Uri.parse('https://www.centralbank.org.bb/exchange-rates'))
          .timeout(const Duration(seconds: 15));
      if (pageResponse.statusCode != 200) return null;

      final csrfToken = _extractCsrfToken(pageResponse.body);
      if (csrfToken == null) return null;

      // Step 2: POST to the API endpoint (cookies are handled by the Client)
      final apiResponse = await client
          .post(
            Uri.parse('https://www.centralbank.org.bb/get_exchange_rates'),
            headers: {
              'X-CSRF-TOKEN': csrfToken,
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': 'https://www.centralbank.org.bb/exchange-rates',
            },
            body: {
              'dateDropDown': 'Y',
              'IsHome': 'N',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (apiResponse.statusCode != 200) return null;

      return parseCbbBarbadosJson(apiResponse.body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static String? _extractCsrfToken(String html) {
    final match = RegExp(
      r'name="csrf-token" content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(1);
  }

  @visibleForTesting
  static Map<String, double>? parseCbbBarbadosJson(String jsonText) {
    try {
      final jsonData = jsonDecode(jsonText) as Map<String, dynamic>;
      final html = jsonData['html'] as String?;
      if (html == null || html.isEmpty) return null;
      return _parseCbbBarbadosHtml(html);
    } catch (_) {
      return null;
    }
  }

  static Map<String, double>? _parseCbbBarbadosHtml(String html) {
    // Find the Notes tab (cat_n) – it's the first active tab.
    final notesMatch = RegExp(
      r'id="cat_n"[^>]*>.*?<tbody>(.*?)</tbody>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);

    if (notesMatch == null) return null;
    final notesHtml = notesMatch.group(1)!;

    final rawRates = <String, double>{};
    final rowRegex = RegExp(
      r'<tr><td>([^<]+)</td><td>([0-9.]+)</td><td>([0-9.]+)</td></tr>',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(notesHtml)) {
      final name = match.group(1)!.trim();
      final buying = double.tryParse(match.group(2)!);
      final selling = double.tryParse(match.group(3)!);
      if (buying == null || selling == null || buying <= 0 || selling <= 0) {
        continue;
      }

      final currency = _currencyNameToCode(name);
      if (currency == null) continue;

      rawRates[currency] = (buying + selling) / 2.0;
    }

    if (!rawRates.containsKey('EUR')) return null;

    // Rates are quoted as BBD per unit of foreign currency.
    rawRates['BBD'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  static String? _currencyNameToCode(String name) {
    switch (name) {
      case 'Belizean Dollar':
        return 'BZD';
      case 'East Caribbean Dollar':
        return 'XCD';
      case 'United States Dollar':
        return 'USD';
      case 'Canadian Dollar':
        return 'CAD';
      case 'Pound Sterling':
        return 'GBP';
      case 'Euro':
        return 'EUR';
      case 'Guyana Dollar':
        return 'GYD';
      default:
        return null;
    }
  }

  @override
  List<String> get supportedCurrencies => [
    'BBD', 'BZD', 'CAD', 'EUR', 'GBP', 'USD', 'XCD',
  ];
}

class BangladeshBankProvider implements CurrencyProvider {
  @override
  String get id => 'bangladesh_bank';

  @override
  String get name => 'Bangladesh Bank';

  @override
  String get initials => 'BB';

  @override
  Future<Map<String, double>?> fetchRates() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.bb.org.bd/en/index.php/econdata/exchangerate'),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      return parseBangladeshBankHtml(response.body);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double>? parseBangladeshBankHtml(String html) {
    final rawRates = <String, double>{};

    // Match rows with currency code followed by at least two numeric columns
    // (Bid Rate, Ask Rate). Works for both the USD table (4 cols) and the
    // Cross Rates table (3 cols).
    final rowRegex = RegExp(
      r'<tr>\s*<td>([A-Z]{3,4})</td>\s*<td>([0-9.]+)</td>\s*<td>([0-9.]+)</td>',
      caseSensitive: false,
    );

    for (final match in rowRegex.allMatches(html)) {
      var currency = match.group(1)!.trim().toUpperCase();
      final bid = double.tryParse(match.group(2)!);
      final ask = double.tryParse(match.group(3)!);
      if (bid == null || ask == null || bid <= 0 || ask <= 0) continue;

      // CNH (offshore yuan) maps to ISO CNY
      if (currency == 'CNH') currency = 'CNY';

      rawRates[currency] = (bid + ask) / 2.0;
    }

    if (!rawRates.containsKey('EUR')) return null;

    // Rates are quoted as BDT per unit of foreign currency.
    rawRates['BDT'] = 1.0;
    return _normalizeToEurBase(rawRates);
  }

  @override
  List<String> get supportedCurrencies => [
    'AUD', 'BDT', 'CAD', 'CNY', 'EUR', 'GBP', 'INR', 'JPY', 'LKR', 'SEK',
    'SGD', 'USD',
  ];
}

CurrencyProvider getCurrencyProviderById(String id) {
  return currencyProviders.firstWhere(
    (p) => p.id == id,
    orElse: () => currencyProviders.first,
  );
}
