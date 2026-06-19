import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/constants.dart';

void main() {
  group('Malaysia statutory helpers', () {
    test('EPF employee 11% of gross', () {
      expect(epfEe(5000), closeTo(550, 0.001));
    });
    test('EPF employer rate 13% when gross <= 5000', () {
      expect(epfEr(5000), closeTo(650, 0.001));
    });
    test('EPF employer rate 12% when gross > 5000', () {
      expect(epfEr(5001), closeTo(600.12, 0.001));
    });

    // SOCSO & EIS use the PERKESO RM100 wage-band table (midpoint method),
    // capped at the RM6,000 insured-wage ceiling (effective 1 Oct 2024).
    test('SOCSO employee capped at 29.75 (RM6,000 ceiling)', () {
      expect(socsoEe(100000), closeTo(29.75, 0.001)); // top band 5,900-6,000
      expect(socsoEe(2000), closeTo(9.75, 0.001));    // band 1,900-2,000 → mid 1,950 × 0.5%
    });
    test('SOCSO employer capped at 104.15 (RM6,000 ceiling)', () {
      expect(socsoEr(100000), closeTo(104.15, 0.001));
      expect(socsoEr(2000), closeTo(34.15, 0.001));   // mid 1,950 × 1.75%
    });

    test('EIS employee capped at 11.90 (RM6,000 ceiling)', () {
      expect(eisEe(100000), closeTo(11.90, 0.001));
      expect(eisEe(1000), closeTo(1.90, 0.001));      // band 900-1,000 → mid 950 × 0.2%
    });
    test('EIS employer 0.2% capped at 11.90 (RM6,000 ceiling)', () {
      expect(eisEr(100000), closeTo(11.90, 0.001));   // was 0.4% — corrected to 0.2%
      expect(eisEr(1000), closeTo(1.90, 0.001));
    });
  });

  group('SST rate map', () {
    test('contains expected keys', () {
      expect(sstRates.containsKey('none'), isTrue);
      expect(sstRates.containsKey('sst5'), isTrue);
      expect(sstRates.containsKey('sst10'), isTrue);
      expect(sstRates.containsKey('service6'), isTrue);
      expect(sstRates.containsKey('service8'), isTrue);
    });

    test('service tax 6% is 0.06', () {
      expect(sstRates['service6']!.rate, closeTo(0.06, 0.0001));
    });
  });

  group('defaultRates', () {
    test('MYR base is 1.0', () {
      expect(defaultRates['MYR'], 1.0);
    });
    test('USD is present', () {
      expect(defaultRates.containsKey('USD'), isTrue);
    });
  });
}
