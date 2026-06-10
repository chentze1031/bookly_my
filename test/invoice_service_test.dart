import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/models.dart';
import 'package:bookly_my/services/invoice_service.dart';

InvoiceItem _item(String desc, double qty, double price) =>
    InvoiceItem(desc: desc, qty: qty, price: price);

void main() {
  group('InvoiceService subtotal/tax/total', () {
    test('subtotal sums qty*price', () {
      final items = [_item('A', 2, 100), _item('B', 1, 50)];
      expect(InvoiceService.subtotal(items), closeTo(250, 0.001));
    });

    test('tax is 6% of subtotal', () {
      expect(InvoiceService.tax(1000), closeTo(60, 0.001));
    });

    test('total includes SST 6%', () {
      final items = [_item('A', 2, 100)];
      expect(InvoiceService.total(items), closeTo(212, 0.001));
    });
  });
}
