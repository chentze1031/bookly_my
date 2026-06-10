import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/accounting_models.dart';

ArInvoice _baseInvoice({
  double total = 1000,
  double amountPaid = 0,
  String dueDate = '2026-06-01',
  InvoiceStatus status = InvoiceStatus.sent,
}) {
  return ArInvoice(
    id: 1,
    invNo: 'INV-2026-0001',
    customerId: 'c1',
    customerName: 'Acme',
    issueDate: '2026-05-01',
    dueDate: dueDate,
    subtotal: total,
    sstAmount: 0,
    total: total,
    amountPaid: amountPaid,
    status: status,
    items: const [],
  );
}

void main() {
  group('ArInvoice.balance', () {
    test('equals total - amountPaid', () {
      expect(_baseInvoice(total: 1000, amountPaid: 400).balance, closeTo(600, 0.001));
    });
  });

  group('InvoiceStatusExt.fromString', () {
    test('known status maps correctly', () {
      expect(InvoiceStatusExt.fromString('paid'), InvoiceStatus.paid);
    });
    test('unknown status falls back to draft', () {
      expect(InvoiceStatusExt.fromString('nope'), InvoiceStatus.draft);
    });
  });

  group('ArInvoice serialization', () {
    test('round-trips status name', () {
      final inv = _baseInvoice(status: InvoiceStatus.partial);
      final restored = ArInvoice.fromMap(inv.toMap());
      expect(restored.status, InvoiceStatus.partial);
    });
  });

  group('AgingSummary.total', () {
    test('sums buckets', () {
      const s = AgingSummary(
        current: 100,
        days1to30: 50,
        days31to60: 25,
        days61to90: 10,
        days90plus: 5,
      );
      expect(s.total, closeTo(190, 0.001));
    });
  });

  group('GlAccountSummary', () {
    test('balance is debit - credit', () {
      const g = GlAccountSummary(code: '1000', name: 'Cash', type: 'Asset', debit: 500, credit: 120);
      expect(g.balance, closeTo(380, 0.001));
      expect(g.absBalance, closeTo(380, 0.001));
    });
  });

  group('Supplier', () {
    test('round-trips supplier', () {
      const s = Supplier(id: 1, name: 'Supplier A', regNo: 'REG-1');
      final restored = Supplier.fromMap(s.toMap());
      expect(restored.name, 'Supplier A');
    });
  });
}
