import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/utils.dart';

void main() {
  group('fmtMYR', () {
    test('formats positive amount', () {
      expect(fmtMYR(1234.5), 'RM 1,234.50');
    });
    test('formats zero', () {
      expect(fmtMYR(0), 'RM 0.00');
    });
    test('formats negative as absolute', () {
      expect(fmtMYR(-50), 'RM 50.00');
    });
  });

  group('fmtShort', () {
    test('thousands abbreviated', () {
      expect(fmtShort(1500), 'RM 1.5k');
    });
    test('small values keep full format', () {
      expect(fmtShort(250), 'RM 250.00');
    });
  });

  group('fmtDate', () {
    test('returns formatted date for valid iso', () {
      final result = fmtDate('2026-01-15', 'en');
      expect(result, contains('15'));
    });
    test('returns fallback for invalid iso', () {
      expect(fmtDate('bad', 'en'), 'bad');
    });
  });

  group('nowISO', () {
    test('returns yyyy-MM-dd format', () {
      final v = nowISO();
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v), isTrue);
    });
  });
}
