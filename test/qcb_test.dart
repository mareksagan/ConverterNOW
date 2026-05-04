import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QcbProvider', () {
    test('id and name are correct', () {
      final provider = QcbProvider();
      expect(provider.id, 'qcb');
      expect(provider.name, 'Qatar Central Bank');
      expect(provider.initials, 'QCB');
    });

    test('fetchRates works with live API', () async {
      final provider = QcbProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('QAR'), isTrue);
      expect(rates['USD'], greaterThan(0));
      expect(rates['QAR'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
