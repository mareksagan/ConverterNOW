import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BotProvider', () {
    test('id and name are correct', () {
      final provider = BotProvider();
      expect(provider.id, 'bot');
      expect(provider.name, 'Bank of Thailand');
      expect(provider.initials, 'BOT');
    });

    test('fetchRates works with live API', () async {
      final provider = BotProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('THB'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['THB'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
