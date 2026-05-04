import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleJson = r'''
{"html":"<div class=\"tab-content\" id=\"myTabContentsub\"><div class=\"tab-pane fade show active\" id=\"cat_n\" role=\"tabpanel\" aria-labelledby=\"cat_n-tab\"><table><thead><tr><th>Currency<\/th><th>Buying<\/th><th>Selling<\/th><\/tr><\/thead><tbody><tr><td>Belizean Dollar<\/td><td>1.000000<\/td><td>1.000000<\/td><\/tr><tr><td>East Caribbean Dollar<\/td><td>0.737040<\/td><td>0.744450<\/td><\/tr><tr><td>United States Dollar<\/td><td>1.980000<\/td><td>2.028570<\/td><\/tr><tr><td>Canadian Dollar<\/td><td>1.450910<\/td><td>1.493830<\/td><\/tr><tr><td>Pound Sterling<\/td><td>2.653430<\/td><td>2.765170<\/td><\/tr><tr><td>Euro<\/td><td>2.292920<\/td><td>2.389480<\/td><\/tr><\/tbody><\/table><\/div><div class=\"tab-pane fade show \" id=\"cat_s\" role=\"tabpanel\" aria-labelledby=\"cat_s-tab\"><table><thead><tr><th>Currency<\/th><th>Buying<\/th><th>Selling<\/th><\/tr><\/thead><tbody><tr><td>Belizean Dollar<\/td><td>0.996880<\/td><td>1.003130<\/td><\/tr><tr><td>East Caribbean Dollar<\/td><td>0.738430<\/td><td>0.743060<\/td><\/tr><tr><td>Guyana Dollar<\/td><td>0.009610<\/td><td>0.009670<\/td><\/tr><tr><td>United States Dollar<\/td><td>1.990000<\/td><td>2.027680<\/td><\/tr><tr><td>Canadian Dollar<\/td><td>1.459170<\/td><td>1.492520<\/td><\/tr><tr><td>Pound Sterling<\/td><td>2.692370<\/td><td>2.748000<\/td><\/tr><tr><td>Euro<\/td><td>2.326570<\/td><td>2.374650<\/td><\/tr><\/tbody><\/table><\/div><\/div>","selecthtml":"","datehtml":""}
''';

void main() {
  group('CbbBarbadosProvider', () {
    test('id, name and initials are correct', () {
      final p = CbbBarbadosProvider();
      expect(p.id, 'cbb_barbados');
      expect(p.name, 'Central Bank of Barbados');
      expect(p.initials, 'CBB');
    });

    test('parseCbbBarbadosJson computes mid rates from Notes tab', () {
      final rates = CbbBarbadosProvider.parseCbbBarbadosJson(_sampleJson);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(1.0, 0.0001));
      // EUR mid = (2.292920 + 2.389480) / 2 = 2.341200
      // USD mid = (1.980000 + 2.028570) / 2 = 2.004285
      // USD normalized = 2.341200 / 2.004285 ≈ 1.1681
      expect(rates['USD'], closeTo(1.1681, 0.0001));
      // BBD normalized = 2.341200 / 1.0 = 2.3412
      expect(rates['BBD'], closeTo(2.3412, 0.0001));
      // GBP mid = (2.653430 + 2.765170) / 2 = 2.709300
      // GBP normalized = 2.341200 / 2.709300 ≈ 0.8641
      expect(rates['GBP'], closeTo(0.8641, 0.0001));
      // XCD mid = (0.737040 + 0.744450) / 2 = 0.740745
      // XCD normalized = 2.341200 / 0.740745 ≈ 3.1606
      expect(rates['XCD'], closeTo(3.1606, 0.0001));
    });

    test('parseCbbBarbadosJson ignores unsupported currencies', () {
      final json = _sampleJson.replaceAll('Euro', 'Swiss Franc');
      final rates = CbbBarbadosProvider.parseCbbBarbadosJson(json);
      expect(rates, isNull);
    });

    test('parseCbbBarbadosJson returns null for missing html', () {
      expect(
        CbbBarbadosProvider.parseCbbBarbadosJson('{"error":"test"}'),
        isNull,
      );
    });

    test('parseCbbBarbadosJson returns null for empty html', () {
      expect(
        CbbBarbadosProvider.parseCbbBarbadosJson('{"html":""}'),
        isNull,
      );
    });

    test('fetchRates returns EUR-based rates or null', () async {
      final rates = await CbbBarbadosProvider().fetchRates();
      if (rates == null) {
        print('CBB Barbados live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BBD'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
