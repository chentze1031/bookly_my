import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../services/inventory_service.dart';
import '../state/app_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY L10N (follows app-wide lang setting)
// ════════════════════════════════════════════════════════════════════════════
class _T {
  final bool zh;
  const _T(this.zh);
  String get inventory   => zh ? '库存' : 'Inventory';
  String get products    => zh ? '产品' : 'Products';
  String get reports     => zh ? '报表' : 'Reports';
  String get lowStock    => zh ? '低库存' : 'Low Stock';
  String get out         => zh ? '缺货' : 'Out';
  String get value       => zh ? '总值' : 'Value';
  String get all         => zh ? '全部' : 'All';
  String get searchHint  => zh ? '搜索名称、SKU、分类...' : 'Search name, SKU, category...';
  String get inStock     => zh ? '有货' : 'In Stock';
  String get outOfStock  => zh ? '缺货' : 'Out of Stock';
  String get negative    => zh ? '负库存' : 'Negative';
  String get addItem     => zh ? '添加产品' : 'Add Item';
  String get editItem    => zh ? '编辑产品' : 'Edit Item';
  String get newItem     => zh ? '新产品' : 'New Item';
  String get noResults   => zh ? '没有找到结果' : 'No results found';
  String get noInventory => zh ? '还没有库存' : 'No inventory yet';
  String get trysearch   => zh ? '换个关键词试试' : 'Try a different search';
  String get addFirst    => zh ? '添加第一个产品' : 'Add your first product';
  String get details     => zh ? '详情' : 'Details';
  String get history     => zh ? '历史' : 'History';
  String get currentStock=> zh ? '当前库存' : 'Current Stock';
  String get stockIn     => zh ? '入库' : 'Stock In';
  String get stockOut    => zh ? '出库' : 'Stock Out';
  String get setQty      => zh ? '设置' : 'Set';
  String get qty         => zh ? '数量' : 'Quantity';
  String get newQty      => zh ? '新数量' : 'New quantity';
  String get reason      => zh ? '原因' : 'Reason';
  String get noteOpt     => zh ? '备注（可选）' : 'Note (optional)';
  String get apply       => zh ? '确定' : 'Apply';
  String get validNum    => zh ? '请输入有效数字' : 'Enter a valid number';
  String get sellPrice   => zh ? '售价' : 'Sell Price';
  String get costPrice   => zh ? '成本价' : 'Cost Price';
  String get marginL     => zh ? '毛利率' : 'Margin';
  String get stockValue  => zh ? '库存价值' : 'Stock Value';
  String get lowAlert    => zh ? '低库存提醒' : 'Low Stock Alert';
  String get category    => zh ? '分类' : 'Category';
  String get notes       => zh ? '备注' : 'Notes';
  String get deleteItem  => zh ? '删除产品' : 'Delete Item';
  String get deleteConfirm => zh ? '将同时删除其全部历史记录，无法撤销。' : 'Its history will also be deleted. This cannot be undone.';
  String get cancel      => zh ? '取消' : 'Cancel';
  String get delete      => zh ? '删除' : 'Delete';
  String get save        => zh ? '保存修改' : 'Save Changes';
  String get nameReq     => zh ? '产品名称必填' : 'Product name is required.';
  String get nameLabel   => zh ? '产品名称 *' : 'PRODUCT NAME *';
  String get skuLabel    => zh ? 'SKU / 条码' : 'SKU / BARCODE';
  String get unitLabel   => zh ? '单位' : 'UNIT';
  String get catLabel    => zh ? '分类' : 'CATEGORY';
  String get costLabel   => zh ? '成本价 (RM)' : 'COST PRICE (RM)';
  String get sellLabel   => zh ? '售价 (RM)' : 'SELL PRICE (RM)';
  String get qtyLabel    => zh ? '数量' : 'QUANTITY';
  String get lowLabel    => zh ? '低库存提醒' : 'LOW STOCK ALERT';
  String get notesLabel  => zh ? '备注' : 'NOTES';
  String get photo       => zh ? '产品图片' : 'PRODUCT PHOTO';
  String get takePhoto   => zh ? '拍照' : 'Camera';
  String get gallery     => zh ? '相册' : 'Gallery';
  String get removePhoto => zh ? '移除' : 'Remove';
  String get noHistory   => zh ? '暂无记录' : 'No movements yet';
  String get last30      => zh ? '近 30 天' : '30 days';
  String get last90      => zh ? '近 90 天' : '90 days';
  String get valueTrend  => zh ? '库存总值趋势' : 'Stock Value Trend';
  String get topSellers  => zh ? '最畅销产品' : 'Top Sellers';
  String get slowMovers  => zh ? '滞销产品' : 'Slow Movers';
  String get lowList     => zh ? '低库存预警' : 'Low Stock Alerts';
  String get soldSuffix  => zh ? '已售' : 'sold';
  String get noSales     => zh ? '该时段无销售' : 'No sales in this period';
  String get allHealthy  => zh ? '库存全部健康 👍' : 'All stock levels healthy 👍';
  String get restock     => zh ? '补货' : 'Restock';
  String get scanBarcode => zh ? '扫描条码' : 'Scan Barcode';
  String get pointCamera => zh ? '对准条形码' : 'Point camera at barcode';
  String get enterManually => zh ? '手动输入' : 'Enter manually';
  String get invoiceRef  => zh ? '发票' : 'Invoice';
}

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY SCREEN (Products + Reports tabs)
// ════════════════════════════════════════════════════════════════════════════
class InventoryScreen extends StatefulWidget {
  /// [embedded] = true when shown as a bottom-nav tab: the app shell already
  /// provides the AppBar, so this screen must not render its own.
  final bool embedded;
  const InventoryScreen({super.key, this.embedded = false});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query  = '';
  String _filter = 'all'; // all | low | out
  int    _tab    = 0;     // 0 products | 1 reports

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
      context.read<InventoryState>().load());
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  void _showForm({InventoryItem? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<InventoryState>(),
        child: _ItemFormSheet(item: item),
      ),
    );
  }

  void _showDetail(InventoryItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<InventoryState>(),
        child: _ItemDetailSheet(
          itemId: item.id,
          onEdit: () { Navigator.pop(context); _showForm(item: item); },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryState>();
    final t   = _T(context.watch<AppState>().settings.lang == 'zh');
    final fmt = NumberFormat('#,##0.00');

    List<InventoryItem> display = inv.search(_query);
    if (_filter == 'low') display = display.where((i) => i.isLowStock && !i.isOutOfStock).toList();
    if (_filter == 'out') display = display.where((i) => i.isOutOfStock).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: widget.embedded ? null : AppBar(
        title: Text('📦  ${t.inventory}'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: t.addItem, onPressed: () => _showForm()),
        ],
      ),
      body: Column(children: [

        // ── Tab switch ─────────────────────────────────────────────────
        Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            for (final (i, label) in [(0, t.products), (1, t.reports)])
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _tab == i ? kDark : kBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label, textAlign: TextAlign.center, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: _tab == i ? Colors.white : kMuted)),
                ),
              )),
          ]),
        ),

        Expanded(child: _tab == 1
          ? _ReportsTab(t: t, onRestock: _showDetail)
          : Column(children: [

          // ── Summary strip ──────────────────────────────────────────
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              _StatChip(label: t.products, value: '${inv.totalProducts}',       color: kText),
              _StatChip(label: t.lowStock, value: '${inv.lowStock.length}',     color: Colors.orange),
              _StatChip(label: t.out,      value: '${inv.outOfStock.length}',   color: kRed),
              _StatChip(label: t.value,    value: 'RM ${fmt.format(inv.totalValue)}', color: kGreen),
            ]),
          ),

          // ── Search ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: t.searchHint,
                hintStyle: const TextStyle(color: kMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: kMuted, size: 20),
                suffixIcon: _query.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: kMuted),
                  onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                ) : null,
                filled: true, fillColor: kSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),

          // ── Filter chips ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              for (final f in [('all', t.all), ('low', '⚠️ ${t.lowStock}'), ('out', '🔴 ${t.out}')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:  _filter == f.$1 ? kDark : kSurface,
                        border: Border.all(color: _filter == f.$1 ? kDark : kBorder),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(f.$2, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _filter == f.$1 ? Colors.white : kMuted)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),

          // ── List ───────────────────────────────────────────────────
          Expanded(child: inv.loading
            ? const Center(child: CircularProgressIndicator(color: kDark, strokeWidth: 2))
            : display.isEmpty
              ? _EmptyState(t: t, hasItems: inv.items.isNotEmpty, onAdd: () => _showForm())
              : RefreshIndicator(
                  onRefresh: inv.load,
                  color: kDark,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ItemCard(
                      item: display[i], t: t,
                      onTap: () => _showDetail(display[i]),
                    ),
                  ),
                ),
          ),
        ])),
      ]),
      floatingActionButton: _tab == 0 ? FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: kDark,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ) : null,
    );
  }
}

// ── Product thumbnail (image or category emoji) ──────────────────────────────
class _Thumb extends StatelessWidget {
  final InventoryItem item;
  final double size;
  const _Thumb({required this.item, this.size = 50});

  static String _catIcon(String? cat) {
    const map = {'Food': '🍔', 'Drink': '🥤', 'Electronics': '📱', 'Clothing': '👕',
                 'Beauty': '💄', 'Health': '💊', 'Office': '📎', 'Tools': '🔧'};
    return map[cat] ?? '📦';
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: size, height: size, color: kBg,
      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
        ? Image.network(item.imageUrl!, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(child: Text(_catIcon(item.category), style: TextStyle(fontSize: size * 0.5))),
            loadingBuilder: (c, child, p) => p == null ? child :
              const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kMuted))))
        : Center(child: Text(_catIcon(item.category), style: TextStyle(fontSize: size * 0.5))),
    ),
  );
}

// ── Item card ─────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final _T t;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.t, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    Color statusColor; String statusLabel;
    if (item.isNegative)        { statusColor = kRed;           statusLabel = t.negative; }
    else if (item.isOutOfStock) { statusColor = kRed;           statusLabel = t.outOfStock; }
    else if (item.isLowStock)   { statusColor = Colors.orange;  statusLabel = t.lowStock; }
    else                        { statusColor = kGreen;         statusLabel = t.inStock; }

    // stock bar: qty relative to 3x low-stock threshold
    final cap = (item.lowStockAt <= 0 ? 10.0 : item.lowStockAt * 3);
    final ratio = (item.qty / cap).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: item.isOutOfStock ? kRedBd : item.isLowStock ? const Color(0xFFFFCC80) : kBorder),
        ),
        child: Row(children: [
          _Thumb(item: item),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item.sku.isNotEmpty)
              Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 11, color: kMuted)),
            const SizedBox(height: 5),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text('${NumberFormat('#,##0.##').format(item.qty)} ${item.unit}',
                style: TextStyle(fontSize: 12, color: item.isNegative ? kRed : kMuted,
                  fontWeight: item.isNegative ? FontWeight.w700 : FontWeight.w400)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio, minHeight: 4,
                backgroundColor: kBg, color: statusColor),
            ),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('RM ${fmt.format(item.sellPrice)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
            Text('${t.costPrice}: ${fmt.format(item.costPrice)}', style: const TextStyle(fontSize: 10, color: kMuted)),
            Text('${item.margin.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10,
              color: item.margin >= 20 ? kGreen : Colors.orange, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }
}

// ── Detail sheet (Details + History tabs) ─────────────────────────────────────
class _ItemDetailSheet extends StatefulWidget {
  final int itemId;
  final VoidCallback onEdit;
  const _ItemDetailSheet({required this.itemId, required this.onEdit});
  @override State<_ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<_ItemDetailSheet> {
  int _tab = 0;
  Future<List<StockMovement>>? _movs;

  @override
  Widget build(BuildContext context) {
    final inv  = context.watch<InventoryState>();
    final t    = _T(context.watch<AppState>().settings.lang == 'zh');
    final item = inv.byId(widget.itemId);
    if (item == null) return const SizedBox.shrink(); // deleted while open
    final fmt  = NumberFormat('#,##0.00');
    _movs ??= inv.movementsFor(widget.itemId);

    return DraggableScrollableSheet(
      initialChildSize: 0.78, maxChildSize: 0.95, minChildSize: 0.45,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 12),
              Row(children: [
                _Thumb(item: item, size: 44),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.sku.isNotEmpty) Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 11, color: kMuted)),
                ])),
                IconButton(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined, color: kMuted)),
                IconButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (dCtx) => AlertDialog(
                      title: Text(t.deleteItem),
                      content: Text('"${item.name}"\n${t.deleteConfirm}'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(t.cancel)),
                        TextButton(onPressed: () => Navigator.pop(dCtx, true),  child: Text(t.delete, style: const TextStyle(color: kRed))),
                      ],
                    ));
                    if (ok == true) {
                      await inv.deleteItem(item.id);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.delete_outline, color: kRed),
                ),
              ]),
              const SizedBox(height: 8),
              // tabs
              Row(children: [
                for (final (i, label) in [(0, t.details), (1, '📜 ${t.history}')])
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _tab == i ? kDark : kBg,
                        borderRadius: BorderRadius.circular(9)),
                      child: Text(label, textAlign: TextAlign.center, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: _tab == i ? Colors.white : kMuted)),
                    ),
                  )),
              ]),
            ]),
          ),
          const SizedBox(height: 6),
          const Divider(color: kBorder, height: 1),

          Expanded(child: _tab == 1
            ? _HistoryList(t: t, item: item, future: _movs!)
            : ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
                _StockAdjustCard(item: item, t: t,
                  onApplied: () => setState(() => _movs = inv.movementsFor(widget.itemId))),
                const SizedBox(height: 16),
                _DetailRow(t.sellPrice,   'RM ${fmt.format(item.sellPrice)}'),
                _DetailRow(t.costPrice,   'RM ${fmt.format(item.costPrice)}'),
                _DetailRow(t.marginL,     '${item.margin.toStringAsFixed(1)}%'),
                _DetailRow(t.stockValue,  'RM ${fmt.format(item.stockValue)}'),
                _DetailRow(t.lowAlert,    '${item.lowStockAt} ${item.unit}'),
                if (item.category != null) _DetailRow(t.category, item.category!),
                if (item.notes?.isNotEmpty == true) _DetailRow(t.notes, item.notes!),
              ])),
        ]),
      ),
    );
  }
}

// ── History list ──────────────────────────────────────────────────────────────
class _HistoryList extends StatelessWidget {
  final _T t;
  final InventoryItem item;
  final Future<List<StockMovement>> future;
  const _HistoryList({required this.t, required this.item, required this.future});

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StockMovement>>(
    future: future,
    builder: (_, snap) {
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator(color: kDark, strokeWidth: 2));
      }
      final movs = snap.data!;
      if (movs.isEmpty) {
        return Center(child: Text(t.noHistory, style: const TextStyle(color: kMuted, fontSize: 13)));
      }
      final qfmt = NumberFormat('#,##0.##');
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: movs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final m = movs[i];
          final (emoji, en, zh) = StockMovement.typeLabel(m.type);
          final dt = DateTime.tryParse(m.createdAt);
          final when = dt == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(dt.toLocal());
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.zh ? '$zh $en' : '$en $zh',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
                Text(when, style: const TextStyle(fontSize: 10, color: kMuted)),
                if (m.invoiceNo?.isNotEmpty == true)
                  Text('${t.invoiceRef}: ${m.invoiceNo}', style: const TextStyle(fontSize: 11, color: kBlue)),
                if (m.note?.isNotEmpty == true)
                  Text(m.note!, style: const TextStyle(fontSize: 11, color: kMuted)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${m.isIn ? '+' : ''}${qfmt.format(m.qtyChange)} ${item.unit}',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                    color: m.isIn ? kGreen : kRed)),
                Text('${qfmt.format(m.qtyBefore)} → ${qfmt.format(m.qtyAfter)}',
                  style: const TextStyle(fontSize: 10, color: kMuted)),
              ]),
            ]),
          );
        },
      );
    },
  );
}

// ── Stock adjust card (with reason + note) ────────────────────────────────────
class _StockAdjustCard extends StatefulWidget {
  final InventoryItem item;
  final _T t;
  final VoidCallback onApplied;
  const _StockAdjustCard({required this.item, required this.t, required this.onApplied});
  @override State<_StockAdjustCard> createState() => _StockAdjustCardState();
}

class _StockAdjustCardState extends State<_StockAdjustCard> {
  final _qtyCtrl  = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _mode    = 'in';       // in | out | set
  String _reason  = 'purchase'; // movement type
  bool   _busy    = false;
  String? _err;

  static const _inReasons  = ['purchase', 'return', 'adjust'];
  static const _outReasons = ['sale', 'damaged', 'return', 'adjust'];

  @override
  void dispose() { _qtyCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _apply() async {
    final t   = widget.t;
    final val = double.tryParse(_qtyCtrl.text);
    if (val == null || val < 0) { setState(() => _err = t.validNum); return; }
    setState(() { _busy = true; _err = null; });
    final inv  = context.read<InventoryState>();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    try {
      if (_mode == 'set') {
        await inv.setQty(widget.item.id, val, note: note);
      } else {
        await inv.applyMovement(widget.item.id, _reason,
          _mode == 'in' ? val : -val, note: note);
      }
      _qtyCtrl.clear(); _noteCtrl.clear();
      widget.onApplied();
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _err = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t    = widget.t;
    final fmt  = NumberFormat('#,##0.##');
    final item = widget.item;
    final reasons = _mode == 'in' ? _inReasons : _outReasons;
    if (_mode != 'set' && !reasons.contains(_reason)) _reason = reasons.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Column(children: [
        Text(t.currentStock, style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 4),
        Text('${fmt.format(item.qty)} ${item.unit}',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: item.isOutOfStock ? kRed : item.isLowStock ? Colors.orange : kText)),
        const SizedBox(height: 14),

        // Mode selector
        Row(children: [
          for (final m in [('in', '📥 ${t.stockIn}', kGreen), ('out', '📤 ${t.stockOut}', kRed), ('set', '✏️ ${t.setQty}', kMuted)])
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _mode = m.$1; _err = null; }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: EdgeInsets.only(right: m.$1 != 'set' ? 6 : 0),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color:  _mode == m.$1 ? m.$3.withValues(alpha: 0.12) : kSurface,
                  border: Border.all(color: _mode == m.$1 ? m.$3 : kBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(m.$2, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: _mode == m.$1 ? m.$3 : kMuted)),
              ),
            )),
        ]),

        // Reason chips (not for 'set' mode)
        if (_mode != 'set') ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft,
            child: Text(t.reason, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5))),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in reasons)
              GestureDetector(
                onTap: () => setState(() => _reason = r),
                child: Builder(builder: (_) {
                  final (emoji, en, zh) = StockMovement.typeLabel(r);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _reason == r ? kDark : kSurface,
                      border: Border.all(color: _reason == r ? kDark : kBorder),
                      borderRadius: BorderRadius.circular(99)),
                    child: Text('$emoji ${t.zh ? zh : en}', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _reason == r ? Colors.white : kMuted)),
                  );
                }),
              ),
          ]),
        ],
        const SizedBox(height: 12),

        // Qty input + Apply
        Row(children: [
          Expanded(child: TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: _mode == 'set' ? t.newQty : t.qty,
              suffixText: item.unit,
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _busy ? null : _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: _mode == 'out' ? kRed : _mode == 'set' ? kDark : kGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(t.apply, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),

        // Note
        TextField(
          controller: _noteCtrl,
          decoration: InputDecoration(
            hintText: t.noteOpt,
            hintStyle: const TextStyle(fontSize: 12, color: kMuted),
            filled: true, fillColor: kSurface, isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
        ),

        if (_err != null) ...[
          const SizedBox(height: 8),
          Text(_err!, style: const TextStyle(color: kRed, fontSize: 12)),
        ],
      ]),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: kMuted)),
      const Spacer(),
      Flexible(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText))),
    ]),
  );
}

// ── Add/Edit form sheet (with photo) ──────────────────────────────────────────
class _ItemFormSheet extends StatefulWidget {
  final InventoryItem? item;
  const _ItemFormSheet({this.item});
  @override State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _name     = TextEditingController();
  final _sku      = TextEditingController();
  final _cost     = TextEditingController();
  final _sell     = TextEditingController();
  final _qty      = TextEditingController();
  final _lowStock = TextEditingController();
  final _notes    = TextEditingController();
  String  _unit   = 'pcs';
  String? _category;
  bool    _saving = false;
  String? _saveError;
  XFile?  _pickedImage;     // new photo waiting to upload
  String? _existingImage;   // already-uploaded URL
  bool    _removeImage = false;

  static const _units = ['pcs', 'kg', 'g', 'litre', 'ml', 'box', 'pack', 'set', 'pair', 'roll'];
  static const _cats  = ['Food', 'Drink', 'Electronics', 'Clothing', 'Beauty', 'Health', 'Office', 'Tools', 'Other'];

  @override
  void initState() {
    super.initState();
    final e = widget.item;
    if (e != null) {
      _name.text     = e.name;
      _sku.text      = e.sku;
      _cost.text     = e.costPrice.toString();
      _sell.text     = e.sellPrice.toString();
      _qty.text      = e.qty.toString();
      _lowStock.text = e.lowStockAt.toString();
      _notes.text    = e.notes ?? '';
      _unit          = e.unit;
      _category      = e.category;
      _existingImage = e.imageUrl;
    } else {
      _qty.text      = '0';
      _lowStock.text = '5';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _cost, _sell, _qty, _lowStock, _notes]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final f = await ImagePicker().pickImage(
        source: src, maxWidth: 800, maxHeight: 800, imageQuality: 80);
      if (f != null && mounted) setState(() { _pickedImage = f; _removeImage = false; });
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    }
  }

  Future<void> _save(_T t) async {
    if (_name.text.trim().isEmpty) { setState(() => _saveError = t.nameReq); return; }
    setState(() { _saving = true; _saveError = null; });
    FocusManager.instance.primaryFocus?.unfocus();

    final inv = context.read<InventoryState>();
    final item = InventoryItem(
      id:         widget.item?.id ?? 0,
      name:       _name.text.trim(),
      sku:        _sku.text.trim(),
      unit:       _unit,
      costPrice:  double.tryParse(_cost.text) ?? 0,
      sellPrice:  double.tryParse(_sell.text) ?? 0,
      qty:        double.tryParse(_qty.text)  ?? 0,
      lowStockAt: double.tryParse(_lowStock.text) ?? 5,
      category:   _category,
      notes:      _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      imageUrl:   _removeImage ? null : _existingImage,
      createdAt:  widget.item?.createdAt ?? DateTime.now().toIso8601String(),
      updatedAt:  DateTime.now().toIso8601String(),
    );

    try {
      if (widget.item == null) {
        await inv.addItem(item, image: _pickedImage);
      } else {
        // qty edits in the form are recorded as 'adjust' movements
        final oldQty = widget.item!.qty;
        await inv.updateItem(item.copyWith(qty: oldQty), image: _pickedImage);
        if (item.qty != oldQty) {
          await inv.setQty(item.id, item.qty, note: 'Edited in form / 表单修改');
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() {
        _saving    = false;
        _saveError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t      = _T(context.watch<AppState>().settings.lang == 'zh');
    final isEdit = widget.item != null;
    final hasImage = _pickedImage != null || (_existingImage != null && !_removeImage);

    return DraggableScrollableSheet(
      initialChildSize: 0.92, maxChildSize: 0.96, minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 12),
              Text(isEdit ? t.editItem : t.newItem, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── Photo ───────────────────────────────────────────
                _Field(label: t.photo, child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 80, height: 80, color: kBg,
                      child: _pickedImage != null
                        ? Image.file(File(_pickedImage!.path), fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(child: Text('🖼️', style: TextStyle(fontSize: 28))))
                        : (hasImage
                            ? Image.network(_existingImage!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(child: Text('📦', style: TextStyle(fontSize: 32))))
                            : const Center(child: Text('📦', style: TextStyle(fontSize: 32)))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
                    _PhotoBtn(icon: Icons.photo_camera_outlined, label: t.takePhoto,
                      onTap: () => _pickImage(ImageSource.camera)),
                    _PhotoBtn(icon: Icons.photo_library_outlined, label: t.gallery,
                      onTap: () => _pickImage(ImageSource.gallery)),
                    if (hasImage)
                      _PhotoBtn(icon: Icons.delete_outline, label: t.removePhoto, danger: true,
                        onTap: () => setState(() { _pickedImage = null; _removeImage = true; })),
                  ])),
                ])),

                _Field(label: t.nameLabel, child: _tf(_name, 'e.g. Nasi Lemak Bungkus')),
                _Field(label: t.skuLabel, child: Row(children: [
                  Expanded(child: _tf(_sku, 'e.g. NLB-001')),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => _BarcodeScannerScreen(t: t)),
                      );
                      if (result != null && mounted) setState(() => _sku.text = result);
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Text('📷', style: TextStyle(fontSize: 20))),
                    ),
                  ),
                ])),

                Row(children: [
                  Expanded(child: _Field(label: t.unitLabel, child: _Dropdown(value: _unit, items: _units, onChanged: (v) => setState(() => _unit = v!)))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: t.catLabel, child: _Dropdown(value: _category, items: _cats, nullable: true, onChanged: (v) => setState(() => _category = v)))),
                ]),
                Row(children: [
                  Expanded(child: _Field(label: t.costLabel, child: _tf(_cost, '0.00', isNum: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: t.sellLabel, child: _tf(_sell, '0.00', isNum: true))),
                ]),
                Row(children: [
                  Expanded(child: _Field(label: t.qtyLabel, child: _tf(_qty, '0', isNum: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: t.lowLabel, child: _tf(_lowStock, '5', isNum: true))),
                ]),
                _Field(label: t.notesLabel, child: _tf(_notes, '...', maxLines: 2)),
                const SizedBox(height: 20),

                if (_saveError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: kRedBg, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kRedBd)),
                    child: Text(_saveError!, style: const TextStyle(color: kRed, fontSize: 13)),
                  ),

                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _save(t),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDark, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                    child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isEdit ? t.save : t.addItem, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }


  Widget _tf(TextEditingController ctrl, String hint, {bool isNum = false, int maxLines = 1}) => TextField(
    controller: ctrl,
    keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    maxLines: maxLines,
    style: const TextStyle(fontSize: 14, color: kText),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 13),
      filled: true, fillColor: kBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDark, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
  );
}

class _PhotoBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _PhotoBtn({required this.icon, required this.label, required this.onTap, this.danger = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kBg, border: Border.all(color: danger ? kRedBd : kBorder),
        borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: danger ? kRed : kText),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: danger ? kRed : kText)),
      ]),
    ),
  );
}

// ── Reports tab ───────────────────────────────────────────────────────────────
class _ReportsTab extends StatefulWidget {
  final _T t;
  final void Function(InventoryItem) onRestock;
  const _ReportsTab({required this.t, required this.onRestock});
  @override State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  int _days = 30;
  Future<List<StockMovement>>? _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<InventoryState>().allMovements(days: 90);
  }

  @override
  Widget build(BuildContext context) {
    final t   = widget.t;
    final inv = context.watch<InventoryState>();
    final fmt = NumberFormat('#,##0.00');
    final qfmt = NumberFormat('#,##0.##');

    return FutureBuilder<List<StockMovement>>(
      future: _future,
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: kDark, strokeWidth: 2));
        }
        final all = snap.data!;
        final cutoff = DateTime.now().subtract(Duration(days: _days)).toIso8601String();
        final windowed = all.where((m) => m.createdAt.compareTo(cutoff) >= 0).toList();
        final trend   = inv.valueTrend(windowed, days: _days);
        final top     = inv.topSellers(windowed).take(5).toList();
        final slow    = inv.slowMovers(windowed).take(5).toList();
        final lowList = [...inv.outOfStock, ...inv.lowStock];

        return RefreshIndicator(
          color: kDark,
          onRefresh: () async => setState(() =>
            _future = context.read<InventoryState>().allMovements(days: 90)),
          child: ListView(padding: const EdgeInsets.all(16), children: [

            // period switch
            Row(children: [
              for (final d in [(30, t.last30), (90, t.last90)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _days = d.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _days == d.$1 ? kDark : kSurface,
                        border: Border.all(color: _days == d.$1 ? kDark : kBorder),
                        borderRadius: BorderRadius.circular(99)),
                      child: Text(d.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: _days == d.$1 ? Colors.white : kMuted)),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),

            // ── Value trend ────────────────────────────────────────
            _ReportCard(title: '📈 ${t.valueTrend}', child: SizedBox(
              height: 160,
              child: trend.length < 2
                ? Center(child: Text(t.noHistory, style: const TextStyle(color: kMuted, fontSize: 12)))
                : LineChart(LineChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, interval: (_days / 4).floorToDouble(),
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(DateFormat('d/M').format(trend[i].day),
                              style: const TextStyle(fontSize: 9, color: kMuted)));
                        })),
                    ),
                    lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                        'RM ${fmt.format(s.y)}',
                        const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      )).toList(),
                    )),
                    lineBarsData: [LineChartBarData(
                      spots: [for (int i = 0; i < trend.length; i++) FlSpot(i.toDouble(), trend[i].value)],
                      isCurved: true, curveSmoothness: 0.25,
                      color: kGreen, barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: kGreen.withValues(alpha: 0.08)),
                    )],
                  )),
            )),
            const SizedBox(height: 12),

            // ── Top sellers ────────────────────────────────────────
            _ReportCard(title: '🏆 ${t.topSellers}', child: top.isEmpty
              ? _emptyLine(t.noSales)
              : Column(children: [
                  for (final (i, e) in top.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        SizedBox(width: 22, child: Text('${i + 1}.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                            color: i == 0 ? kGold : kMuted))),
                        Expanded(child: Text(e.item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
                        Text('${qfmt.format(e.sold)} ${e.item.unit} ${t.soldSuffix}',
                          style: const TextStyle(fontSize: 12, color: kGreen, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                ])),
            const SizedBox(height: 12),

            // ── Slow movers ────────────────────────────────────────
            _ReportCard(title: '🐢 ${t.slowMovers}', child: slow.isEmpty
              ? _emptyLine(t.noSales)
              : Column(children: [
                  for (final item in slow)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
                        Text('${qfmt.format(item.qty)} ${item.unit} · RM ${fmt.format(item.stockValue)}',
                          style: const TextStyle(fontSize: 12, color: kMuted)),
                      ]),
                    ),
                ])),
            const SizedBox(height: 12),

            // ── Low stock alerts ───────────────────────────────────
            _ReportCard(title: '⚠️ ${t.lowList}', child: lowList.isEmpty
              ? _emptyLine(t.allHealthy)
              : Column(children: [
                  for (final item in lowList)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        Text(item.isOutOfStock ? '🔴' : '🟠', style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
                        Text('${qfmt.format(item.qty)} ${item.unit}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: item.isOutOfStock ? kRed : Colors.orange)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => widget.onRestock(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(99)),
                            child: Text(t.restock, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                    ),
                ])),
            const SizedBox(height: 80),
          ]),
        );
      },
    );
  }

  Widget _emptyLine(String msg) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(child: Text(msg, style: const TextStyle(fontSize: 12, color: kMuted))));
}

class _ReportCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ReportCard({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
      const SizedBox(height: 10),
      child,
    ]),
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      child,
    ]),
  );
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final bool nullable;
  final ValueChanged<String?> onChanged;
  const _Dropdown({this.value, required this.items, this.nullable = false, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: value,
        isExpanded: true,
        style: const TextStyle(fontSize: 14, color: kText),
        items: [
          if (nullable) const DropdownMenuItem(value: null, child: Text('—', style: TextStyle(color: kMuted))),
          ...items.map((i) => DropdownMenuItem(value: i, child: Text(i))),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
      Text(label, style: const TextStyle(fontSize: 9, color: kMuted)),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  final _T t;
  final bool hasItems;
  final VoidCallback onAdd;
  const _EmptyState({required this.t, required this.hasItems, required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📦', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(hasItems ? t.noResults : t.noInventory, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      const SizedBox(height: 6),
      Text(hasItems ? t.trysearch : t.addFirst, style: const TextStyle(fontSize: 13, color: kMuted)),
      if (!hasItems) ...[
        const SizedBox(height: 20),
        ElevatedButton(onPressed: onAdd,
          style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
          child: Text(t.addItem)),
      ],
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY PRODUCT PICKER (used by invoice screen)
// ════════════════════════════════════════════════════════════════════════════
/// Bottom-sheet product picker. Returns the selected [InventoryItem] or null.
Future<InventoryItem?> showInventoryPicker(BuildContext context) {
  final inv = context.read<InventoryState>();
  final t   = _T(context.read<AppState>().settings.lang == 'zh');
  if (inv.items.isEmpty && !inv.loading) inv.load();
  return showModalBottomSheet<InventoryItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: inv,
      child: _PickerSheet(t: t),
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  final _T t;
  const _PickerSheet({required this.t});
  @override State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final inv  = context.watch<InventoryState>();
    final t    = widget.t;
    final fmt  = NumberFormat('#,##0.00');
    final qfmt = NumberFormat('#,##0.##');
    final list = inv.search(_q);

    return DraggableScrollableSheet(
      initialChildSize: 0.75, maxChildSize: 0.92, minChildSize: 0.4,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 12),
              Text('📦 ${t.inventory}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: t.searchHint,
                  hintStyle: const TextStyle(color: kMuted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: kMuted, size: 20),
                  filled: true, fillColor: kBg, isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ]),
          ),
          Expanded(child: inv.loading
            ? const Center(child: CircularProgressIndicator(color: kDark, strokeWidth: 2))
            : list.isEmpty
              ? Center(child: Text(t.noResults, style: const TextStyle(color: kMuted, fontSize: 13)))
              : ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final item = list[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kBg, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder)),
                        child: Row(children: [
                          _Thumb(item: item, size: 40),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
                            Text('${qfmt.format(item.qty)} ${item.unit}',
                              style: TextStyle(fontSize: 11,
                                color: item.isOutOfStock ? kRed : kMuted,
                                fontWeight: item.isOutOfStock ? FontWeight.w700 : FontWeight.w400)),
                          ])),
                          Text('RM ${fmt.format(item.sellPrice)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kText)),
                        ]),
                      ),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BARCODE SCANNER SCREEN
// ════════════════════════════════════════════════════════════════════════════
class _BarcodeScannerScreen extends StatefulWidget {
  final _T t;
  const _BarcodeScannerScreen({required this.t});
  @override State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    _scanned = true;
    Navigator.pop(context, barcode!.rawValue!);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(t.scanBarcode, style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on, color: Colors.white), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.flip_camera_ios, color: Colors.white), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 260, height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(16)),
              child: const Stack(children: [
                _Corner(top: 0, left: 0, rotate: 0),
                _Corner(top: 0, right: 0, rotate: 90),
                _Corner(bottom: 0, right: 0, rotate: 180),
                _Corner(bottom: 0, left: 0, rotate: 270),
              ]),
            ),
            const SizedBox(height: 20),
            Text(t.pointCamera, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ]),
        ),
        Positioned(
          bottom: 40, left: 0, right: 0,
          child: Center(
            child: TextButton(
              onPressed: () async {
                final ctrl = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: Text(t.enterManually),
                    content: TextField(
                      controller: ctrl, autofocus: true,
                      decoration: const InputDecoration(hintText: 'Barcode / SKU'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(t.cancel)),
                      TextButton(onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()), child: const Text('OK')),
                    ],
                  ),
                );
                if (result?.isNotEmpty == true && context.mounted) {
                  Navigator.pop(context, result);
                }
              },
              child: Text(t.enterManually, style: const TextStyle(
                color: Colors.white70, decoration: TextDecoration.underline, decorationColor: Colors.white70)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Corner extends StatelessWidget {
  final double? top, bottom, left, right;
  final double rotate;
  const _Corner({this.top, this.bottom, this.left, this.right, required this.rotate});
  @override
  Widget build(BuildContext context) => Positioned(
    top: top, bottom: bottom, left: left, right: right,
    child: Transform.rotate(
      angle: rotate * 3.14159 / 180,
      child: Container(
        width: 24, height: 24,
        decoration: const BoxDecoration(
          border: Border(
            top:  BorderSide(color: kGreen, width: 3),
            left: BorderSide(color: kGreen, width: 3))),
      ),
    ),
  );
}
