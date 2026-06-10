import 'package:flutter_test/flutter_test.dart';
import 'package:bookly_my/services/inventory_service.dart';

InventoryItem _item({
  double costPrice = 50,
  double sellPrice = 100,
  double qty = 10,
  double lowStockAt = 5,
}) {
  return InventoryItem(
    id: 1,
    name: 'Widget',
    sku: 'W-001',
    unit: 'pcs',
    costPrice: costPrice,
    sellPrice: sellPrice,
    qty: qty,
    lowStockAt: lowStockAt,
    createdAt: '2026-01-01',
    updatedAt: '2026-01-01',
  );
}

void main() {
  group('InventoryItem computed properties', () {
    test('stockValue = costPrice * qty', () {
      expect(_item(costPrice: 25, qty: 4).stockValue, closeTo(100, 0.001));
    });

    test('margin percent', () {
      expect(_item(costPrice: 40, sellPrice: 100).margin, closeTo(60, 0.001));
    });

    test('margin is 0 when sellPrice is 0', () {
      expect(_item(sellPrice: 0).margin, closeTo(0, 0.001));
    });

    test('isLowStock true when qty <= lowStockAt', () {
      expect(_item(qty: 5, lowStockAt: 5).isLowStock, isTrue);
      expect(_item(qty: 6, lowStockAt: 5).isLowStock, isFalse);
    });

    test('isOutOfStock true when qty <= 0', () {
      expect(_item(qty: 0).isOutOfStock, isTrue);
      expect(_item(qty: 1).isOutOfStock, isFalse);
    });
  });

  group('InventoryItem copyWith', () {
    test('updates qty only', () {
      final updated = _item(qty: 10).copyWith(qty: 25);
      expect(updated.qty, closeTo(25, 0.001));
      expect(updated.name, 'Widget');
    });
  });
}
