import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbbhProvider', () {
    test('id and name are correct', () {
      final provider = CbbhProvider();
      expect(provider.id, 'cbbh');
      expect(provider.name, 'Centralna banka Bosne i Hercegovine');
      expect(provider.initials, 'CBBH');
    });

    test('fetchRates works with live CBBH XML API', () async {
      final provider = CbbhProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BAM'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['BAM'], greaterThan(0));
    });
  });
}
