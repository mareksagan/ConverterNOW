import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BojProvider', () {
    test('id and name are correct', () {
      final provider = BojProvider();
      expect(provider.id, 'boj');
      expect(provider.name, 'Bank of Japan');
      expect(provider.initials, 'BOJ');
    });

    test('fetchRates works with live API', () async {
      final provider = BojProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('JPY'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['JPY'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
