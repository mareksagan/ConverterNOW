import 'dart:convert';
import 'package:converterpro/models/currency_provider.dart';
import 'package:converterpro/models/settings.dart';
import 'package:converterpro/utils/utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Currencies {
  /// Fallback rates only include EUR=1.0 to satisfy SimpleCustomProperty
  /// assertions. All other currencies must come from a live provider.
  static const defaultExchangeRates = {
    'EUR': 1.0,
  };

  /// The conversion rates with respect to EUR
  Map<String, double> exchangeRates;

  /// The ISO 8601 datetime of the last update (e.g. 2026-04-28T10:34:56)
  String lastUpdate;

  /// ID of the provider that supplied the rates
  String providerId;

  Currencies({
    this.exchangeRates = defaultExchangeRates,
    this.lastUpdate = '',
    this.providerId = '',
  });

  /// Transform the exchangeRates map into a json that can be stored
  String toJson() => jsonEncode(exchangeRates);

  /// It transforms a previous stored data (into this object.
  /// Note: only exchange rates are stored; metadata comes from separate prefs.
  factory Currencies.fromJson(String jsonString) {
    Map jsonData = json.decode(jsonString);
    final exchangeRates = <String, double>{};
    for (String key in jsonData.keys) {
      final value = jsonData[key];
      if (value is num) {
        exchangeRates[key] = value.toDouble();
      }
    }
    return Currencies(exchangeRates: exchangeRates);
  }

  Currencies copyWith({
    Map<String, double>? exchangeRates,
    String? lastUpdate,
    String? providerId,
  }) {
    return Currencies(
      exchangeRates: exchangeRates ?? this.exchangeRates,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      providerId: providerId ?? this.providerId,
    );
  }
}

class CurrenciesNotifier extends AsyncNotifier<Currencies> {
  static final provider = AsyncNotifierProvider<CurrenciesNotifier, Currencies>(
    CurrenciesNotifier.new,
  );
  late SharedPreferencesWithCache pref;

  @override
  Future<Currencies> build() async {
    pref = await ref.read(sharedPref.future);

    final String now = DateFormat("yyyy-MM-dd").format(DateTime.now());
    final String currentProviderId =
        ref.watch(currencyProviderIdProvider).value ?? 'inforeuro';

    print('[CurrenciesNotifier] build() provider=$currentProviderId');

    // Let's search before if we already have downloaded the exchange rates
    String? lastUpdateDate = pref.getString("lastUpdateCurrenciesDate");
    String? lastProviderId = pref.getString("lastCurrencyProviderId");

    // if I have never updated the conversions, if I have updated before today
    // or if the provider changed, I have to update
    if (!(ref.read(revokeInternetProvider).value ?? false) &&
        (lastUpdateDate == null ||
            lastUpdateDate != now ||
            lastProviderId != currentProviderId)) {
      print('[CurrenciesNotifier] Downloading for $currentProviderId (lastDate=$lastUpdateDate, lastProvider=$lastProviderId, today=$now)');
      return _downloadCurrencies(currentProviderId);
    }
    // If I already have the data of today I just use it, no need of read them
    // from the web
    print('[CurrenciesNotifier] Reading saved data (lastDate=$lastUpdateDate, lastProvider=$lastProviderId, today=$now)');
    return _readSavedCurrencies();
  }

  void forceCurrenciesDownload(String? providerId) async {
    final String currentProviderId = providerId ??
        ref.read(currencyProviderIdProvider).value ?? 'inforeuro';
    print('[CurrenciesNotifier] forceCurrenciesDownload: $currentProviderId');
    state = AsyncData(await _downloadCurrencies(currentProviderId));
  }

  Currencies _readSavedCurrencies() {
    String? lastUpdate = pref.getString('lastUpdateCurrencies');
    String? providerId = pref.getString('lastCurrencyProviderId');
    String? currenciesRead = pref.getString('currenciesRates');
    print('[CurrenciesNotifier] _readSavedCurrencies: providerId=$providerId, lastUpdate=$lastUpdate, hasData=${currenciesRead != null}');
    if (currenciesRead != null) {
      final saved = Currencies.fromJson(
        currenciesRead,
      ).copyWith(lastUpdate: lastUpdate, providerId: providerId);
      // Filter saved data to only include currencies supported by the provider
      final provider = getCurrencyProviderById(providerId ?? 'inforeuro');
      final allowed = provider.supportedCurrencies.toSet();
      allowed.add('EUR');
      final filteredRates = Map<String, double>.fromEntries(
        saved.exchangeRates.entries.where((e) => allowed.contains(e.key)),
      );
      print('[CurrenciesNotifier] Read ${filteredRates.length} saved currencies for ${providerId ?? 'inforeuro'}');
      return saved.copyWith(exchangeRates: filteredRates);
    }
    print('[CurrenciesNotifier] No saved data found, returning empty Currencies()');
    return Currencies();
  }

  /// Updates the currencies exchange rates with the latest values. It will also
  /// update the status at the end (updated or error)
  Future<Currencies> _downloadCurrencies(String providerId) async {
    print('[CurrenciesNotifier] _downloadCurrencies: $providerId');
    final provider = getCurrencyProviderById(providerId);
    try {
      final rates = await provider.fetchRates();
      print('[CurrenciesNotifier] fetchRates returned: ${rates != null ? '${rates.length} rates' : 'null'}');
      if (rates != null && rates.isNotEmpty) {
        var lastUpdate = DateFormat("yyyy-MM-ddTHH:mm:ss").format(DateTime.now());
        var lastUpdateDate = DateFormat("yyyy-MM-dd").format(DateTime.now());
        // Only use what the provider returns — no hardcoded fallbacks.
        final allowed = provider.supportedCurrencies.toSet();
        allowed.add('EUR');
        final mergedRates = Map<String, double>.from(Currencies.defaultExchangeRates);
        for (final entry in rates.entries) {
          if (allowed.contains(entry.key)) {
            mergedRates[entry.key] = entry.value;
          }
        }
        await pref.setString('currenciesRates', jsonEncode(mergedRates));
        await pref.setString('lastUpdateCurrencies', lastUpdate);
        await pref.setString('lastUpdateCurrenciesDate', lastUpdateDate);
        await pref.setString('lastCurrencyProviderId', providerId);
        print('[CurrenciesNotifier] Downloaded ${mergedRates.length} currencies for $providerId');
        return Currencies(
          exchangeRates: mergedRates,
          lastUpdate: lastUpdate,
          providerId: providerId,
        );
      }
      print('[CurrenciesNotifier] fetchRates returned null or empty, falling back to saved data');
    } catch (e, st) {
      print('[CurrenciesNotifier] ERROR during download: $e');
      print('[CurrenciesNotifier] Stack: $st');
    }
    return _readSavedCurrencies();
  }
}
