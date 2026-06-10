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

    test('SOCSO employee capped at 14.10', () {
      expect(socsoEe(100000), closeTo(14.10, 0.001));
      expect(socsoEe(2000), closeTo(10.0, 0.001));
    });
    test('SOCSO employer capped at 49.40', () {
      expect(socsoEr(100000), closeTo(49.40, 0.001));
      expect(socsoEr(2000), closeTo(35.0, 0.001));
    });

    test('EIS employee capped at 3.90', () {
      expect(eisEe(100000), closeTo(3.90, 0.001));
      expect(eisEe(1000), closeTo(2.0, 0.001));
    });
    test('EIS employer capped at 7.90', () {
      expect(eisEr(100000), closeTo(7.90, 0.001));
      expect(eisEr(1000), closeTo(4.0, 0.001));
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
