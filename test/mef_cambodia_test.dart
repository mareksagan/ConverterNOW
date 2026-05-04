import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MefCambodiaProvider', () {
    test('id and name are correct', () {
      final provider = MefCambodiaProvider();
      expect(provider.id, 'mef_cambodia');
      expect(provider.name, 'Ministry of Economy and Finance (Cambodia)');
      expect(provider.initials, 'MEF');
    });

    test('fetchRates works with live API', () async {
      final provider = MefCambodiaProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('KHR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['KHR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
