import 'package:converterpro/models/currency_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BsiProvider', () {
    test('id and name are correct', () {
      final provider = BsiProvider();
      expect(provider.id, 'bsi');
      expect(provider.name, 'Bank of Slovenia');
      expect(provider.initials, 'BSI');
    });

    test('parses sample XML correctly', () {
      final provider = BsiProvider();
      // ignore: invalid_use_of_visible_for_testing_member
      final rates = provider.parseBsiXml(_sampleXml);

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));

      // BAM is pegged to EUR at 1.95583 BAM/EUR → 1 BAM ≈ 0.5113 EUR
      expect(rates['BAM'], closeTo(0.5113, 0.0001));

      // RSD ≈ 117.49 RSD/EUR → 1 RSD ≈ 0.00851 EUR
      expect(rates['RSD'], closeTo(0.00851, 0.00001));

      // AZN ≈ 1.9532 AZN/EUR → 1 AZN ≈ 0.5120 EUR
      expect(rates['AZN'], closeTo(0.5120, 0.0001));
    });

    test('fetchRates works with live API', () async {
      final provider = BsiProvider();
      final rates = await provider.fetchRates();

      expect(rates, isNotNull);
      expect(rates, isNotEmpty);
      expect(rates!.containsKey('EUR'), isTrue);
      expect(rates['EUR'], equals(1.0));
      expect(rates.containsKey('BAM'), isTrue);
      expect(rates['BAM'], greaterThan(0));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

const _sampleXml = '''<?xml version="1.0"?>
<EksotTecBS xmlns="http://www.bsi.si" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.bsi.si http://www.bsi.si/_data/tecajnice/EksotTecBS.xsd">
<tecajnica datum="2026-03-31" veljavnost="2026-04-01">
<tecaj oznaka="ALL" sifra="008">95.990</tecaj>
<tecaj oznaka="DZD" sifra="012">153.13</tecaj>
<tecaj oznaka="ARS" sifra="032">1606.2</tecaj>
<tecaj oznaka="BSD" sifra="044">1.1493</tecaj>
<tecaj oznaka="BHD" sifra="048">0.43592</tecaj>
<tecaj oznaka="BDT" sifra="050">141.06</tecaj>
<tecaj oznaka="AMD" sifra="051">433.69</tecaj>
<tecaj oznaka="BBD" sifra="052">2.2986</tecaj>
<tecaj oznaka="BMD" sifra="060">1.1493</tecaj>
<tecaj oznaka="BTN" sifra="064">108.97</tecaj>
<tecaj oznaka="BOB" sifra="068">7.9411</tecaj>
<tecaj oznaka="BWP" sifra="072">16.395</tecaj>
<tecaj oznaka="BZD" sifra="084">2.2986</tecaj>
<tecaj oznaka="SBD" sifra="090">9.1724</tecaj>
<tecaj oznaka="BND" sifra="096">1.4813</tecaj>
<tecaj oznaka="MMK" sifra="104">2416.9</tecaj>
<tecaj oznaka="BIF" sifra="108">3414.0</tecaj>
<tecaj oznaka="KHR" sifra="116">4605.0</tecaj>
<tecaj oznaka="CVE" sifra="132">110.65</tecaj>
<tecaj oznaka="KYD" sifra="136">0.94244</tecaj>
<tecaj oznaka="LKR" sifra="144">362.25</tecaj>
<tecaj oznaka="CLP" sifra="152">1067.1</tecaj>
<tecaj oznaka="COP" sifra="170">4220.6</tecaj>
<tecaj oznaka="KMF" sifra="174">491.96</tecaj>
<tecaj oznaka="CRC" sifra="188">534.18</tecaj>
<tecaj oznaka="CUP" sifra="192">27.583</tecaj>
<tecaj oznaka="DOP" sifra="214">69.321</tecaj>
<tecaj oznaka="SVC" sifra="222">10.056</tecaj>
<tecaj oznaka="ETB" sifra="230">178.10</tecaj>
<tecaj oznaka="ERN" sifra="232">17.240</tecaj>
<tecaj oznaka="FKP" sifra="238">0.86851</tecaj>
<tecaj oznaka="FJD" sifra="242">2.5833</tecaj>
<tecaj oznaka="DJF" sifra="262">204.32</tecaj>
<tecaj oznaka="GMD" sifra="270">84.351</tecaj>
<tecaj oznaka="GIP" sifra="292">0.86851</tecaj>
<tecaj oznaka="GTQ" sifra="320">8.7876</tecaj>
<tecaj oznaka="GNF" sifra="324">10079</tecaj>
<tecaj oznaka="GYD" sifra="328">240.32</tecaj>
<tecaj oznaka="HTG" sifra="332">150.56</tecaj>
<tecaj oznaka="HNL" sifra="340">30.481</tecaj>
<tecaj oznaka="IRR" sifra="364">1509347</tecaj>
<tecaj oznaka="IQD" sifra="368">1505.6</tecaj>
<tecaj oznaka="JMD" sifra="388">180.82</tecaj>
<tecaj oznaka="KZT" sifra="398">547.91</tecaj>
<tecaj oznaka="JOD" sifra="400">0.81439</tecaj>
<tecaj oznaka="KES" sifra="404">149.37</tecaj>
<tecaj oznaka="KPW" sifra="408">149.06</tecaj>
<tecaj oznaka="KWD" sifra="414">0.35572</tecaj>
<tecaj oznaka="KGS" sifra="417">100.48</tecaj>
<tecaj oznaka="LAK" sifra="418">25217</tecaj>
<tecaj oznaka="LBP" sifra="422">102964</tecaj>
<tecaj oznaka="LSL" sifra="426">19.643</tecaj>
<tecaj oznaka="LRD" sifra="430">210.37</tecaj>
<tecaj oznaka="LYD" sifra="434">7.3372</tecaj>
<tecaj oznaka="MOP" sifra="446">9.2797</tecaj>
<tecaj oznaka="MWK" sifra="454">1989.7</tecaj>
<tecaj oznaka="MVR" sifra="462">17.501</tecaj>
<tecaj oznaka="MUR" sifra="480">54.098</tecaj>
<tecaj oznaka="MNT" sifra="496">4096.8</tecaj>
<tecaj oznaka="MDL" sifra="498">20.317</tecaj>
<tecaj oznaka="MAD" sifra="504">10.766</tecaj>
<tecaj oznaka="OMR" sifra="512">0.44243</tecaj>
<tecaj oznaka="NAD" sifra="516">19.643</tecaj>
<tecaj oznaka="NPR" sifra="524">173.91</tecaj>
<tecaj oznaka="XCG" sifra="532">2.0572</tecaj>
<tecaj oznaka="AWG" sifra="533">2.0572</tecaj>
<tecaj oznaka="VUV" sifra="548">138.32</tecaj>
<tecaj oznaka="NIO" sifra="558">42.300</tecaj>
<tecaj oznaka="NGN" sifra="566">1591.6</tecaj>
<tecaj oznaka="PKR" sifra="586">321.03</tecaj>
<tecaj oznaka="PAB" sifra="590">1.1493</tecaj>
<tecaj oznaka="PGK" sifra="598">4.9603</tecaj>
<tecaj oznaka="PYG" sifra="600">7445.2</tecaj>
<tecaj oznaka="PEN" sifra="604">4.0243</tecaj>
<tecaj oznaka="QAR" sifra="634">4.1910</tecaj>
<tecaj oznaka="RWF" sifra="646">1679.2</tecaj>
<tecaj oznaka="SHP" sifra="654">0.86858</tecaj>
<tecaj oznaka="SAR" sifra="682">4.3134</tecaj>
<tecaj oznaka="SCR" sifra="690">16.460</tecaj>
<tecaj oznaka="VND" sifra="704">30273</tecaj>
<tecaj oznaka="SOS" sifra="706">656.82</tecaj>
<tecaj oznaka="SSP" sifra="728">5240.3</tecaj>
<tecaj oznaka="SZL" sifra="748">19.643</tecaj>
<tecaj oznaka="SYP" sifra="760">132.47</tecaj>
<tecaj oznaka="TOP" sifra="776">2.6954</tecaj>
<tecaj oznaka="TTD" sifra="780">7.7351</tecaj>
<tecaj oznaka="AED" sifra="784">4.2215</tecaj>
<tecaj oznaka="TND" sifra="788">3.3812</tecaj>
<tecaj oznaka="UGX" sifra="800">4319.9</tecaj>
<tecaj oznaka="MKD" sifra="807">61.667</tecaj>
<tecaj oznaka="EGP" sifra="818">62.725</tecaj>
<tecaj oznaka="TZS" sifra="834">2964.0</tecaj>
<tecaj oznaka="UYU" sifra="858">46.682</tecaj>
<tecaj oznaka="UZS" sifra="860">14013</tecaj>
<tecaj oznaka="WST" sifra="882">3.1609</tecaj>
<tecaj oznaka="YER" sifra="886">274.18</tecaj>
<tecaj oznaka="TWD" sifra="901">36.836</tecaj>
<tecaj oznaka="SLE" sifra="925">27.727</tecaj>
<tecaj oznaka="VES" sifra="928">539.29</tecaj>
<tecaj oznaka="MRU" sifra="929">45.869</tecaj>
<tecaj oznaka="STN" sifra="930">24.518</tecaj>
<tecaj oznaka="TMT" sifra="934">4.0226</tecaj>
<tecaj oznaka="GHS" sifra="936">12.619</tecaj>
<tecaj oznaka="SDG" sifra="938">688.24</tecaj>
<tecaj oznaka="RSD" sifra="941">117.49</tecaj>
<tecaj oznaka="MZN" sifra="943">73.138</tecaj>
<tecaj oznaka="AZN" sifra="944">1.9532</tecaj>
<tecaj oznaka="XAF" sifra="950">655.95</tecaj>
<tecaj oznaka="XCD" sifra="951">3.1031</tecaj>
<tecaj oznaka="XOF" sifra="952">655.94</tecaj>
<tecaj oznaka="XPF" sifra="953">119.25</tecaj>
<tecaj oznaka="XAU" sifra="959">127.95</tecaj>
<tecaj oznaka="XDR" sifra="960">0.84644</tecaj>
<tecaj oznaka="XAG" sifra="961">2.0375</tecaj>
<tecaj oznaka="XPT" sifra="962">53.506</tecaj>
<tecaj oznaka="XPD" sifra="964">40.653</tecaj>
<tecaj oznaka="ZMW" sifra="967">22.078</tecaj>
<tecaj oznaka="SRD" sifra="968">43.031</tecaj>
<tecaj oznaka="MGA" sifra="969">4807.1</tecaj>
<tecaj oznaka="AFN" sifra="971">73.798</tecaj>
<tecaj oznaka="TJS" sifra="972">10.927</tecaj>
<tecaj oznaka="AOA" sifra="973">1048.3</tecaj>
<tecaj oznaka="CDF" sifra="976">2585.6</tecaj>
<tecaj oznaka="BAM" sifra="977">1.95583</tecaj>
<tecaj oznaka="UAH" sifra="980">50.402</tecaj>
<tecaj oznaka="GEL" sifra="981">3.1002</tecaj>
</tecajnica>
</EksotTecBS>''';
