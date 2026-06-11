import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY MODELS
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
  final String? imageUrl;  // Supabase Storage public URL
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
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  double get stockValue   => costPrice * qty;
  double get margin       => sellPrice > 0 ? ((sellPrice - costPrice) / sellPrice * 100) : 0;
  bool   get isLowStock   => qty <= lowStockAt;
  bool   get isOutOfStock => qty <= 0;
  bool   get isNegative   => qty < 0;

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
    imageUrl:   m['image_url'] as String?,
    createdAt:  m['created_at'] as String? ?? '',
    updatedAt:  m['updated_at'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'name':         name,
    'sku':          sku,
    'unit':         unit,
    'cost_price':   costPrice,
    'sell_price':   sellPrice,
    'qty':          qty,
    'low_stock_at': lowStockAt,
    'category':     category,
    'notes':        notes,
    'image_url':    imageUrl,
    'updated_at':   DateTime.now().toIso8601String(),
  };

  InventoryItem copyWith({
    String? name, String? sku, String? unit,
    double? costPrice, double? sellPrice,
    double? qty, double? lowStockAt,
    String? category, String? notes, String? imageUrl,
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
    imageUrl:   imageUrl   ?? this.imageUrl,
  );
}

// ─── Stock movement (immutable audit record) ─────────────────────────────────
/// type: purchase | sale | return | damaged | adjust
class StockMovement {
  final int     id;
  final int     itemId;
  final String  type;
  final double  qtyChange;   // +in / -out
  final double  qtyBefore;
  final double  qtyAfter;
  final String? note;
  final String? invoiceNo;
  final String  createdAt;

  const StockMovement({
    required this.id,
    required this.itemId,
    required this.type,
    required this.qtyChange,
    required this.qtyBefore,
    required this.qtyAfter,
    this.note,
    this.invoiceNo,
    required this.createdAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> m) => StockMovement(
    id:        m['id'] as int,
    itemId:    m['item_id'] as int,
    type:      m['type'] as String? ?? 'adjust',
    qtyChange: (m['qty_change'] as num?)?.toDouble() ?? 0,
    qtyBefore: (m['qty_before'] as num?)?.toDouble() ?? 0,
    qtyAfter:  (m['qty_after']  as num?)?.toDouble() ?? 0,
    note:      m['note'] as String?,
    invoiceNo: m['invoice_no'] as String?,
    createdAt: m['created_at'] as String? ?? '',
  );

  bool get isIn => qtyChange >= 0;

  /// Bilingual label: (emoji, en, zh)
  static (String, String, String) typeLabel(String type) => switch (type) {
    'purchase' => ('📥', 'Purchase', '采购'),
    'sale'     => ('📤', 'Sale', '销售'),
    'return'   => ('↩️', 'Return', '退货'),
    'damaged'  => ('🗑️', 'Damaged', '损耗'),
    _          => ('✏️', 'Adjust', '调整'),
  };
}

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY STATE (ChangeNotifier)
// ════════════════════════════════════════════════════════════════════════════
class InventoryState extends ChangeNotifier {
  List<InventoryItem> _items = [];
  bool _loading = false;
  String? _error;

  List<InventoryItem> get items         => _items;
  bool                get loading       => _loading;
  String?             get error         => _error;
  List<InventoryItem> get lowStock      => _items.where((i) => i.isLowStock && !i.isOutOfStock).toList();
  List<InventoryItem> get outOfStock    => _items.where((i) => i.isOutOfStock).toList();
  double              get totalValue    => _items.fold(0, (s, i) => s + i.stockValue);
  int                 get totalProducts => _items.length;

  static SupabaseClient get _db => Supabase.instance.client;

  InventoryItem? byId(int id) {
    final idx = _items.indexWhere((i) => i.id == id);
    return idx == -1 ? null : _items[idx];
  }

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

  // ── Image upload (Supabase Storage: bucket 'product-images') ─────────────
  /// Returns public URL, or throws with a clean message.
  Future<String> uploadImage(XFile file) async {
    try {
      final uid   = _db.auth.currentUser?.id ?? 'anon';
      final ext   = file.path.split('.').last.toLowerCase();
      final path  = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await File(file.path).readAsBytes();
      await _db.storage.from('product-images').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(contentType: 'image/$ext', upsert: false),
      );
      return _db.storage.from('product-images').getPublicUrl(path);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Bucket not found')) {
        throw Exception('Storage bucket "product-images" not found. '
            'Run the SQL setup in Supabase Dashboard. / 未找到图片存储桶，请先在 Supabase 后台运行配置脚本。');
      }
      throw Exception('Image upload failed / 图片上传失败: $msg');
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────
  Future<void> addItem(InventoryItem item, {XFile? image}) async {
    try {
      String? imageUrl = item.imageUrl;
      if (image != null) imageUrl = await uploadImage(image);
      final map = item.copyWith(imageUrl: imageUrl).toMap()
        ..['created_at'] = DateTime.now().toIso8601String();
      final row = await _db.from('inventory').insert(map).select().single();
      final newItem = InventoryItem.fromMap(row);
      _items = [newItem, ..._items]..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      // Opening stock counts as a purchase movement
      if (newItem.qty != 0) {
        await _insertMovement(newItem.id, 'purchase', newItem.qty, 0, newItem.qty,
            note: 'Opening stock / 期初库存');
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('relation "inventory" does not exist')) {
        throw Exception('Inventory table not found. Please run the SQL setup in Supabase Dashboard. / 库存表不存在，请先在 Supabase 后台运行配置脚本。');
      } else if (msg.contains('row-level security')) {
        throw Exception('Database permission error. Please check RLS policy in Supabase. / 数据库权限错误，请检查 RLS 策略。');
      }
      rethrow;
    }
  }

  // ── Update (item details only — qty changes go through applyMovement) ────
  Future<void> updateItem(InventoryItem item, {XFile? image}) async {
    String? imageUrl = item.imageUrl;
    if (image != null) imageUrl = await uploadImage(image);
    final updated = item.copyWith(imageUrl: imageUrl);
    await _db.from('inventory').update(updated.toMap()).eq('id', item.id);
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx != -1) {
      _items = List.from(_items)..[idx] = updated;
      notifyListeners();
    }
  }

  // ── Delete (movements cascade-deleted by FK) ──────────────────────────────
  Future<void> deleteItem(int id) async {
    await _db.from('inventory').delete().eq('id', id);
    _items = _items.where((i) => i.id != id).toList();
    notifyListeners();
  }

  // ── Apply a stock movement: update qty + write audit record ──────────────
  /// [qtyChange] positive = stock in, negative = stock out.
  /// Negative resulting stock is allowed (sell-first-restock-later), UI shows red.
  Future<void> applyMovement(
    int itemId,
    String type,
    double qtyChange, {
    String? note,
    String? invoiceNo,
  }) async {
    if (qtyChange == 0) return;
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    final before = _items[idx].qty;
    final after  = before + qtyChange;

    final updated = _items[idx].copyWith(qty: after);
    await _db.from('inventory').update(updated.toMap()).eq('id', itemId);
    _items = List.from(_items)..[idx] = updated;
    notifyListeners();

    await _insertMovement(itemId, type, qtyChange, before, after,
        note: note, invoiceNo: invoiceNo);
  }

  /// Set absolute qty (manual correction) — records as 'adjust'.
  Future<void> setQty(int itemId, double newQty, {String? note}) async {
    final item = byId(itemId);
    if (item == null) return;
    await applyMovement(itemId, 'adjust', newQty - item.qty, note: note);
  }

  Future<void> _insertMovement(
    int itemId, String type, double change, double before, double after,
    {String? note, String? invoiceNo}) async {
    try {
      await _db.from('stock_movements').insert({
        'item_id':    itemId,
        'type':       type,
        'qty_change': change,
        'qty_before': before,
        'qty_after':  after,
        'note':       note,
        'invoice_no': invoiceNo,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Movement logging must never break the stock operation itself.
      debugPrint('stock_movements insert failed: $e');
    }
  }

  // ── Invoice deduction ─────────────────────────────────────────────────────
  /// Deducts stock for invoice line items that carry an 'inv_id' key.
  /// Rows: same Map<String,String> shape used by the invoice screen.
  /// Failures are swallowed (invoice save must not fail because of stock).
  Future<void> deductForInvoice(List<Map<String, String>> rows, String invoiceNo) async {
    for (final r in rows) {
      final invId = int.tryParse(r['inv_id'] ?? '');
      if (invId == null) continue;
      final qty = double.tryParse(r['qty'] ?? '') ?? 0;
      if (qty <= 0) continue;
      try {
        await applyMovement(invId, 'sale', -qty, invoiceNo: invoiceNo);
      } catch (e) {
        debugPrint('Invoice stock deduction failed for item $invId: $e');
      }
    }
  }

  // ── Movement queries ──────────────────────────────────────────────────────
  Future<List<StockMovement>> movementsFor(int itemId, {int limit = 100}) async {
    final rows = await _db.from('stock_movements')
        .select().eq('item_id', itemId)
        .order('created_at', ascending: false).limit(limit);
    return (rows as List).map((r) => StockMovement.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<List<StockMovement>> allMovements({int days = 90}) async {
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final rows = await _db.from('stock_movements')
        .select().gte('created_at', since)
        .order('created_at', ascending: false).limit(2000);
    return (rows as List).map((r) => StockMovement.fromMap(r as Map<String, dynamic>)).toList();
  }

  // ── Report helpers ────────────────────────────────────────────────────────
  /// Top sellers: total qty sold per item within [movements], descending.
  List<({InventoryItem item, double sold})> topSellers(List<StockMovement> movements) {
    final sold = <int, double>{};
    for (final m in movements) {
      if (m.type == 'sale') sold[m.itemId] = (sold[m.itemId] ?? 0) + (-m.qtyChange);
    }
    final out = <({InventoryItem item, double sold})>[];
    for (final e in sold.entries) {
      final item = byId(e.key);
      if (item != null && e.value > 0) out.add((item: item, sold: e.value));
    }
    out.sort((a, b) => b.sold.compareTo(a.sold));
    return out;
  }

  /// Slow movers: items with zero sales in the window, by stock value desc.
  List<InventoryItem> slowMovers(List<StockMovement> movements) {
    final soldIds = movements.where((m) => m.type == 'sale').map((m) => m.itemId).toSet();
    return _items.where((i) => !soldIds.contains(i.id) && i.qty > 0).toList()
      ..sort((a, b) => b.stockValue.compareTo(a.stockValue));
  }

  /// Daily total stock value for the past [days], reconstructed by walking
  /// movements backwards from today's value. Returns oldest→newest.
  List<({DateTime day, double value})> valueTrend(List<StockMovement> movements, {int days = 30}) {
    final today = DateTime.now();
    final costOf = <int, double>{for (final i in _items) i.id: i.costPrice};
    // movement value impact per day (qtyChange * cost)
    final impact = <String, double>{};
    for (final m in movements) {
      final d = m.createdAt.length >= 10 ? m.createdAt.substring(0, 10) : '';
      impact[d] = (impact[d] ?? 0) + m.qtyChange * (costOf[m.itemId] ?? 0);
    }
    final out = <({DateTime day, double value})>[];
    double running = totalValue;
    for (int i = 0; i < days; i++) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      out.add((day: day, value: running < 0 ? 0 : running));
      final key = day.toIso8601String().substring(0, 10);
      running -= impact[key] ?? 0; // step back before this day's movements
    }
    return out.reversed.toList();
  }

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
