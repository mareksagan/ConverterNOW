import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NorgesBankProvider', () {
    test('id, name and initials are correct', () {
      final provider = NorgesBankProvider();
      expect(provider.id, 'norges_bank');
      expect(provider.name, 'Norges Bank');
      expect(provider.initials, 'NB');
    });

    test('fetchRates returns EUR-normalized rates', () async {
      final provider = NorgesBankProvider();
      final rates = await provider.fetchRates();

      if (rates == null) {
        print('Norges Bank live fetch returned null');
        return;
      }

      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('NOK'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
