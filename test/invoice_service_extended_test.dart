import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/services/invoice_service.dart';
import 'package:bookly_my/models.dart';

void main() {
  group('InvoiceService amountInWords', () {
    test('zero', () {
      expect(InvoiceService.amountInWords(0), 'Ringgit Malaysia Zero only');
    });
    test('whole ringgit', () {
      expect(InvoiceService.amountInWords(150), 'Ringgit Malaysia One Hundred Fifty only');
    });
    test('with cents', () {
      expect(InvoiceService.amountInWords(150.50), 'Ringgit Malaysia One Hundred Fifty and cents 50 only');
    });
    test('thousands', () {
      expect(InvoiceService.amountInWords(1250), 'Ringgit Malaysia One Thousand Two Hundred Fifty only');
    });
    test('negative converts to positive', () {
      expect(InvoiceService.amountInWords(-50), contains('Fifty'));
    });
  });

  group('InvoiceService toCsv', () {
    test('generates CSV with headers and totals', () {
      final items = [
        InvoiceItem(desc: 'Item A', qty: 2, price: 100),
        InvoiceItem(desc: 'Item B', qty: 1, price: 50),
      ];
      final csv = InvoiceService.toCsv(items);
      expect(csv, contains('Description,Quantity,Unit Price,Line Total'));
      expect(csv, contains('Item A,2,100.00,200.00'));
      expect(csv, contains('Grand Total,,,265.00'));
    });
  });

  group('InvoiceService sstAmount', () {
    test('default 6% SST', () {
      final items = [InvoiceItem(desc: 'X', qty: 1, price: 100)];
      expect(InvoiceService.sstAmount(items), closeTo(6, 0.001));
    });
    test('custom rate', () {
      final items = [InvoiceItem(desc: 'X', qty: 1, price: 100)];
      expect(InvoiceService.sstAmount(items, rate: 0.10), closeTo(10, 0.001));
    });
  });
}
