import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NrbProvider', () {
    test('id and name are correct', () {
      final provider = NrbProvider();
      expect(provider.id, 'nrb');
      expect(provider.name, 'Nepal Rastra Bank');
      expect(provider.initials, 'NRB');
    });

    test('fetchRates works with live API', () async {
      final provider = NrbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('NPR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['NPR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
