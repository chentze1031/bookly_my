import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY MODEL
// ════════════════════════════════════════════════════════════════════════════
class InventoryItem {
  final int    id;
  final String name;
  final String sku;
  final String unit;       // pcs, kg, box, litre, etc.
  final double costPrice;  // MYR
  final double sellPrice;  // MYR
  final double qty;
  final double lowStockAt; // alert threshold
  final String? category;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  const InventoryItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.unit,
    required this.costPrice,
    required this.sellPrice,
    required this.qty,
    required this.lowStockAt,
    this.category,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  double get stockValue  => costPrice * qty;
  double get margin      => sellPrice > 0 ? ((sellPrice - costPrice) / sellPrice * 100) : 0;
  bool   get isLowStock  => qty <= lowStockAt;
  bool   get isOutOfStock => qty <= 0;

  factory InventoryItem.fromMap(Map<String, dynamic> m) => InventoryItem(
    id:         m['id'] as int,
    name:       m['name'] as String,
    sku:        m['sku'] as String? ?? '',
    unit:       m['unit'] as String? ?? 'pcs',
    costPrice:  (m['cost_price'] as num?)?.toDouble() ?? 0,
    sellPrice:  (m['sell_price'] as num?)?.toDouble() ?? 0,
    qty:        (m['qty'] as num?)?.toDouble() ?? 0,
    lowStockAt: (m['low_stock_at'] as num?)?.toDouble() ?? 5,
    category:   m['category'] as String?,
    notes:      m['notes'] as String?,
    createdAt:  m['created_at'] as String? ?? '',
    updatedAt:  m['updated_at'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'name':        name,
    'sku':         sku,
    'unit':        unit,
    'cost_price':  costPrice,
    'sell_price':  sellPrice,
    'qty':         qty,
    'low_stock_at': lowStockAt,
    'category':    category,
    'notes':       notes,
    'updated_at':  DateTime.now().toIso8601String(),
  };

  InventoryItem copyWith({
    String? name, String? sku, String? unit,
    double? costPrice, double? sellPrice,
    double? qty, double? lowStockAt,
    String? category, String? notes,
  }) => InventoryItem(
    id: id, createdAt: createdAt,
    updatedAt: DateTime.now().toIso8601String(),
    name:       name       ?? this.name,
    sku:        sku        ?? this.sku,
    unit:       unit       ?? this.unit,
    costPrice:  costPrice  ?? this.costPrice,
    sellPrice:  sellPrice  ?? this.sellPrice,
    qty:        qty        ?? this.qty,
    lowStockAt: lowStockAt ?? this.lowStockAt,
    category:   category   ?? this.category,
    notes:      notes      ?? this.notes,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY STATE (ChangeNotifier)
// ════════════════════════════════════════════════════════════════════════════
class InventoryState extends ChangeNotifier {
  List<InventoryItem> _items = [];
  bool _loading = false;
  String? _error;

  List<InventoryItem> get items        => _items;
  bool                get loading      => _loading;
  String?             get error        => _error;
  List<InventoryItem> get lowStock     => _items.where((i) => i.isLowStock && !i.isOutOfStock).toList();
  List<InventoryItem> get outOfStock   => _items.where((i) => i.isOutOfStock).toList();
  double              get totalValue   => _items.fold(0, (s, i) => s + i.stockValue);
  int                 get totalProducts => _items.length;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    _loading = true; _error = null; notifyListeners();
    try {
      final rows = await _db.from('inventory').select().order('name');
      _items = (rows as List).map((r) => InventoryItem.fromMap(r as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false; notifyListeners();
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────
  Future<void> addItem(InventoryItem item) async {
    try {
      final map = item.toMap()..['created_at'] = DateTime.now().toIso8601String();
      final row = await _db.from('inventory').insert(map).select().single();
      final newItem = InventoryItem.fromMap(row as Map<String, dynamic>);
      _items = [newItem, ..._items];
      _items.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
    } catch (e) {
      // Re-throw with cleaner message
      final msg = e.toString();
      if (msg.contains('relation "inventory" does not exist')) {
        throw Exception('Inventory table not found. Please run the SQL setup in Supabase Dashboard.');
      } else if (msg.contains('row-level security')) {
        throw Exception('Database permission error. Please check RLS policy in Supabase.');
      } else {
        throw Exception('Failed to add item: $msg');
      }
    }
  }

  // ── Update ────────────────────────────────────────────────────────────────
  Future<void> updateItem(InventoryItem item) async {
    try {
      await _db.from('inventory').update(item.toMap()).eq('id', item.id);
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _items = List.from(_items)..[idx] = item;
        notifyListeners();
      }
    } catch (e) {
      throw Exception('Failed to update item: $e');
    }
  }

  // ── Adjust qty only ───────────────────────────────────────────────────────
  Future<void> adjustQty(int id, double delta) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final newQty = (_items[idx].qty + delta).clamp(0, double.infinity);
    final updated = _items[idx].copyWith(qty: newQty);
    await updateItem(updated);
  }

  // ── Adjust qty by exact amount (for stock-in / stock-out) ─────────────────
  Future<void> setQty(int id, double newQty) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    final updated = _items[idx].copyWith(qty: newQty.clamp(0, double.infinity));
    await updateItem(updated);
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> deleteItem(int id) async {
    try {
      await _db.from('inventory').delete().eq('id', id);
      _items = _items.where((i) => i.id != id).toList();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to delete item: $e');
    }
  }

  // ── Stock in (add stock) ──────────────────────────────────────────────────
  Future<void> stockIn(int id, double qty, {String? note}) async {
    await adjustQty(id, qty);
  }

  // ── Stock out (reduce stock) ──────────────────────────────────────────────
  Future<void> stockOut(int id, double qty, {String? note}) async {
    await adjustQty(id, -qty);
  }

  // ── Low stock items ───────────────────────────────────────────────────────
  List<InventoryItem> get lowStockItems =>
    _items.where((i) => i.isLowStock).toList()
      ..sort((a, b) => a.qty.compareTo(b.qty));

  // ── Search / filter ───────────────────────────────────────────────────────
  List<InventoryItem> search(String q) {
    if (q.isEmpty) return _items;
    final lower = q.toLowerCase();
    return _items.where((i) =>
      i.name.toLowerCase().contains(lower) ||
      i.sku.toLowerCase().contains(lower) ||
      (i.category?.toLowerCase().contains(lower) ?? false)
    ).toList();
  }
}
