import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleHtml = '''
<table class="solo-table-all cols-5">
  <thead><tr><th>Monnaie</th><th>Taux Acheteur</th><th>Taux Moyen</th><th>Taux Vendeur</th><th>Date</th></tr></thead>
  <tbody>
    <tr>
      <td class="views-field views-field-field-code-pays"> <a href="/node/286" hreflang="fr">DTS</a> </td>
      <td class="views-field views-field-field-acheteur"> 4072.0326 </td>
      <td class="views-field views-field-field-moyen"> 4104.8715 </td>
      <td class="views-field views-field-field-vendeur"> 4137.7105 </td>
      <td class="views-field views-field-field-date"> <time datetime="2026-05-04T12:00:00Z">2026-05-04</time> </td>
    </tr>
    <tr>
      <td class="views-field views-field-field-code-pays"> <a href="/node/145" hreflang="fr">EUR</a> </td>
      <td class="views-field views-field-field-acheteur"> 3476.6627 </td>
      <td class="views-field views-field-field-moyen"> 3504.7004 </td>
      <td class="views-field views-field-field-vendeur"> 3532.7380 </td>
      <td class="views-field views-field-field-date"> <time datetime="2026-05-04T12:00:00Z">2026-05-04</time> </td>
    </tr>
    <tr>
      <td class="views-field views-field-field-code-pays"> <a href="/node/144" hreflang="fr">USD</a> </td>
      <td class="views-field views-field-field-acheteur"> 2963.8083 </td>
      <td class="views-field views-field-field-moyen"> 2987.7100 </td>
      <td class="views-field views-field-field-vendeur"> 3011.6117 </td>
      <td class="views-field views-field-field-date"> <time datetime="2026-05-04T12:00:00Z">2026-05-04</time> </td>
    </tr>
  </tbody>
</table>
''';

void main() {
  group('BrbProvider', () {
    test('id, name and initials are correct', () {
      final p = BrbProvider();
      expect(p.id, 'brb');
      expect(p.name, 'Banque de la République du Burundi');
      expect(p.initials, 'BRB');
    });

    test('parseBrbHtml returns raw rates from average column', () {
      final rates = BrbProvider.parseBrbHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!['EUR'], closeTo(3504.7004, 0.0001));
      expect(rates['USD'], closeTo(2987.7100, 0.0001));
      expect(rates['XDR'], closeTo(4104.8715, 0.0001));
    });

    test('parseBrbHtml maps DTS to XDR', () {
      final rates = BrbProvider.parseBrbHtml(_sampleHtml);
      expect(rates, isNotNull);
      expect(rates!.containsKey('DTS'), isFalse);
      expect(rates.containsKey('XDR'), isTrue);
    });

    test('parseBrbHtml returns null for missing EUR', () {
      final html = _sampleHtml.replaceAll('EUR', 'XXX');
      expect(BrbProvider.parseBrbHtml(html), isNull);
    });

    test('parseBrbHtml returns null for empty table', () {
      expect(BrbProvider.parseBrbHtml('<table></table>'), isNull);
    });

    test('fetchRates returns EUR-based rates', () async {
      final rates = await BrbProvider().fetchRates();
      if (rates == null) {
        print('BRB live fetch returned null');
        return;
      }
      expect(rates.containsKey('EUR'), isTrue);
      expect(rates['EUR'], closeTo(1.0, 0.0001));
      expect(rates.containsKey('USD'), isTrue);
      expect(rates.containsKey('BIF'), isTrue);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
