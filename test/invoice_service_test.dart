import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/services/invoice_service.dart';

class _Item implements InvoiceItem {
  @override
  final String desc;
  @override
  final double qty;
  @override
  final double price;
  _Item(this.desc, this.qty, this.price);
}

void main() {
  group('InvoiceService subtotal/tax/total', () {
    test('subtotal sums qty*price', () {
      final items = [_Item('A', 2, 100), _Item('B', 1, 50)];
      expect(InvoiceService.subtotal(items), closeTo(250, 0.001));
    });

    test('tax is 6% of subtotal', () {
      expect(InvoiceService.tax(1000), closeTo(60, 0.001));
    });

    test('total includes SST 6%', () {
      final items = [_Item('A', 2, 100)];
      expect(InvoiceService.total(items), closeTo(212, 0.001));
    });
  });
}
