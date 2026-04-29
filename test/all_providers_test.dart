import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('All providers', () {
    for (final provider in currencyProviders) {
      test('${provider.name} (${provider.id}) fetches rates', () async {
        final rates = await provider.fetchRates();
        expect(rates, isNotNull, reason: '${provider.name} returned null');
        expect(rates, isNotEmpty, reason: '${provider.name} returned empty map');
        expect(rates!.containsKey('EUR'), isTrue, reason: '${provider.name} missing EUR');
      }, timeout: const Timeout(Duration(seconds: 30)));
    }
  });
}
