import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/models.dart';

void main() {
  group('Transaction serialization', () {
    test('toMap/fromMap round-trips core fields', () {
      final tx = Transaction(
        id: 1,
        type: 'expense',
        catId: '5110',
        amountMYR: 120.5,
        origAmount: 120.5,
        origCurrency: 'MYR',
        sstKey: 'none',
        sstMYR: 0,
        descEN: 'Test expense',
        descZH: '测试',
        date: '2026-01-10',
        entries: [JournalEntry(acc: '5110', dc: 'Dr', val: 120.5)],
      );

      final map = tx.toMap();
      final restored = Transaction.fromMap(map);

      expect(restored.id, tx.id);
      expect(restored.type, tx.type);
      expect(restored.catId, tx.catId);
      expect(restored.amountMYR, closeTo(tx.amountMYR, 0.0001));
      expect(restored.date, tx.date);
      expect(restored.entries.length, 1);
      expect(restored.entries.first.acc, '5110');
    });
  });

  group('Customer serialization', () {
    test('toMap/fromMap round-trips customer', () {
      const c = Customer(id: 1, name: 'Acme Sdn Bhd', regNo: '123456-X');
      final restored = Customer.fromMap(c.toMap());
      expect(restored.name, 'Acme Sdn Bhd');
      expect(restored.regNo, '123456-X');
    });
  });

  group('Employee serialization', () {
    test('toMap/fromMap round-trips employee', () {
      const e = Employee(
        id: 1,
        name: 'Ahmad',
        icNo: '900101-01-1234',
        position: 'Accountant',
        department: 'Finance',
        basicSalary: 4500,
      );
      final restored = Employee.fromMap(e.toMap());
      expect(restored.name, 'Ahmad');
      expect(restored.basicSalary, closeTo(4500, 0.001));
    });
  });

  group('AppSettings', () {
    test('defaults are sensible', () {
      const s = AppSettings();
      expect(s.lang, 'en');
      expect(s.displayCurrency, 'MYR');
      expect(s.companyName, '');
    });

    test('toMap/fromMap round-trips settings', () {
      const s = AppSettings(companyName: 'Bookly MY', lang: 'zh', displayCurrency: 'MYR');
      final restored = AppSettings.fromMap(s.toMap());
      expect(restored.companyName, 'Bookly MY');
      expect(restored.lang, 'zh');
    });
  });
}
