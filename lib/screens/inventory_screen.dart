import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../services/inventory_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// INVENTORY SCREEN
// ════════════════════════════════════════════════════════════════════════════
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query     = '';
  String _filter    = 'all'; // all | low | out

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
      context.read<InventoryState>().load());
  }

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
        child: _ItemDetailSheet(item: item, onEdit: () { Navigator.pop(context); _showForm(item: item); }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inv = context.watch<InventoryState>();
    final fmt = NumberFormat('#,##0.00');

    List<InventoryItem> display = inv.search(_query);
    if (_filter == 'low')  display = display.where((i) => i.isLowStock && !i.isOutOfStock).toList();
    if (_filter == 'out')  display = display.where((i) => i.isOutOfStock).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('📦  Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showForm(),
            tooltip: 'Add Item',
          ),
        ],
      ),
      body: Column(
        children: [

          // ── Summary strip ────────────────────────────────────────────
          Container(
            color: kSurface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              _StatChip(label: 'Products', value: '${inv.totalProducts}',          color: kText),
              _StatChip(label: 'Low Stock', value: '${inv.lowStock.length}',        color: Colors.orange),
              _StatChip(label: 'Out',       value: '${inv.outOfStock.length}',      color: kRed),
              _StatChip(label: 'Value',     value: 'RM ${fmt.format(inv.totalValue)}', color: kGreen),
            ]),
          ),

          // ── Search ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search name, SKU, category...',
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

          // ── Filter chips ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              for (final f in [('all', 'All'), ('low', '⚠️ Low Stock'), ('out', '🔴 Out')])
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
                        color: _filter == f.$1 ? Colors.white : kMuted,
                      )),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),

          // ── List ─────────────────────────────────────────────────────
          Expanded(child: inv.loading
            ? const Center(child: CircularProgressIndicator(color: kDark, strokeWidth: 2))
            : display.isEmpty
              ? _EmptyState(hasItems: inv.items.isNotEmpty, onAdd: () => _showForm())
              : RefreshIndicator(
                  onRefresh: inv.load,
                  color: kDark,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _ItemCard(
                      item: display[i],
                      onTap: () => _showDetail(display[i]),
                    ),
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: kDark,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onTap;
  const _ItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    Color statusColor = kGreen;
    String statusLabel = 'In Stock';
    if (item.isOutOfStock) { statusColor = kRed;          statusLabel = 'Out of Stock'; }
    else if (item.isLowStock) { statusColor = Colors.orange; statusLabel = 'Low Stock'; }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: item.isOutOfStock ? kRedBd : item.isLowStock ? const Color(0xFFFFCC80) : kBorder),
        ),
        child: Row(children: [
          // Icon / avatar
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(
              item.category?.isNotEmpty == true ? _catIcon(item.category!) : '📦',
              style: const TextStyle(fontSize: 24),
            )),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item.sku.isNotEmpty)
              Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 11, color: kMuted)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
                child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Text('${item.qty} ${item.unit}', style: const TextStyle(fontSize: 12, color: kMuted)),
            ]),
          ])),

          // Price
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('RM ${fmt.format(item.sellPrice)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
            Text('Cost: RM ${fmt.format(item.costPrice)}', style: const TextStyle(fontSize: 10, color: kMuted)),
            Text('${item.margin.toStringAsFixed(0)}% margin', style: TextStyle(fontSize: 10, color: item.margin >= 20 ? kGreen : Colors.orange, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  String _catIcon(String cat) {
    final map = {'Food': '🍔', 'Drink': '🥤', 'Electronics': '📱', 'Clothing': '👕', 'Beauty': '💄', 'Health': '💊', 'Office': '📎', 'Tools': '🔧'};
    return map[cat] ?? '📦';
  }
}

// ── Detail sheet ──────────────────────────────────────────────────────────────
class _ItemDetailSheet extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onEdit;
  const _ItemDetailSheet({required this.item, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final inv = context.read<InventoryState>();
    final fmt = NumberFormat('#,##0.00');

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kText))),
                IconButton(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, color: kMuted)),
                IconButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                      title: const Text('Delete Item'),
                      content: Text('Delete "${item.name}"? This cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Delete', style: TextStyle(color: kRed))),
                      ],
                    ));
                    if (ok == true) { await inv.deleteItem(item.id); if (context.mounted) Navigator.pop(context); }
                  },
                  icon: const Icon(Icons.delete_outline, color: kRed),
                ),
              ]),
              if (item.sku.isNotEmpty) Text('SKU: ${item.sku}', style: const TextStyle(fontSize: 12, color: kMuted)),
            ]),
          ),
          const Divider(color: kBorder),

          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
            // Stock adjust
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
              child: Column(children: [
                Text('Current Stock', style: const TextStyle(fontSize: 12, color: kMuted)),
                const SizedBox(height: 4),
                Text('${item.qty} ${item.unit}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kText)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _QtyBtn(icon: '-', onTap: () async { await inv.adjustQty(item.id, -1); if (context.mounted) Navigator.pop(context); }),
                  const SizedBox(width: 16),
                  _QtyBtn(icon: '+', onTap: () async { await inv.adjustQty(item.id, 1);  if (context.mounted) Navigator.pop(context); }),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // Details grid
            _DetailRow('Sell Price',  'RM ${fmt.format(item.sellPrice)}'),
            _DetailRow('Cost Price',  'RM ${fmt.format(item.costPrice)}'),
            _DetailRow('Margin',      '${item.margin.toStringAsFixed(1)}%'),
            _DetailRow('Stock Value', 'RM ${fmt.format(item.stockValue)}'),
            _DetailRow('Low Stock Alert', '${item.lowStockAt} ${item.unit}'),
            if (item.category != null) _DetailRow('Category', item.category!),
            if (item.notes?.isNotEmpty == true) _DetailRow('Notes', item.notes!),
          ])),
        ]),
      ),
    );
  }
}

// ── Qty adjust button ─────────────────────────────────────────────────────────
class _QtyBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(icon, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kText))),
    ),
  );
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
      Text(value,  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
    ]),
  );
}

// ── Add/Edit form sheet ───────────────────────────────────────────────────────
class _ItemFormSheet extends StatefulWidget {
  final InventoryItem? item;
  const _ItemFormSheet({this.item});
  @override State<_ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends State<_ItemFormSheet> {
  final _name       = TextEditingController();
  final _sku        = TextEditingController();
  final _cost       = TextEditingController();
  final _sell       = TextEditingController();
  final _qty        = TextEditingController();
  final _lowStock   = TextEditingController();
  final _notes      = TextEditingController();
  String  _unit     = 'pcs';
  String? _category;
  bool    _saving   = false;

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
    } else {
      _qty.text     = '0';
      _lowStock.text = '5';
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
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
      createdAt:  widget.item?.createdAt ?? DateTime.now().toIso8601String(),
      updatedAt:  DateTime.now().toIso8601String(),
    );

    try {
      if (widget.item == null) { await inv.addItem(item); }
      else                     { await inv.updateItem(item); }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.5,
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
              Text(isEdit ? 'Edit Item' : 'New Item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                _Field(label: 'PRODUCT NAME *', child: _tf(_name, 'e.g. Nasi Lemak Bungkus')),
                _Field(label: 'SKU / BARCODE', child: _tf(_sku, 'e.g. NLB-001')),

                // Unit + Category
                Row(children: [
                  Expanded(child: _Field(label: 'UNIT', child: _Dropdown(value: _unit, items: _units, onChanged: (v) => setState(() => _unit = v!)))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: 'CATEGORY', child: _Dropdown(value: _category, items: _cats, nullable: true, onChanged: (v) => setState(() => _category = v)))),
                ]),

                // Prices
                Row(children: [
                  Expanded(child: _Field(label: 'COST PRICE (RM)', child: _tf(_cost, '0.00', isNum: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: 'SELL PRICE (RM)', child: _tf(_sell, '0.00', isNum: true))),
                ]),

                // Qty + Low stock
                Row(children: [
                  Expanded(child: _Field(label: 'QUANTITY', child: _tf(_qty, '0', isNum: true))),
                  const SizedBox(width: 12),
                  Expanded(child: _Field(label: 'LOW STOCK ALERT', child: _tf(_lowStock, '5', isNum: true))),
                ]),

                _Field(label: 'NOTES', child: _tf(_notes, 'Optional notes...', maxLines: 2)),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDark, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(isEdit ? 'Save Changes' : 'Add Item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
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
  final bool hasItems;
  final VoidCallback onAdd;
  const _EmptyState({required this.hasItems, required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📦', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(hasItems ? 'No results found' : 'No inventory yet', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      const SizedBox(height: 6),
      Text(hasItems ? 'Try a different search' : 'Add your first product', style: const TextStyle(fontSize: 13, color: kMuted)),
      if (!hasItems) ...[
        const SizedBox(height: 20),
        ElevatedButton(onPressed: onAdd,
          style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
          child: const Text('Add Item')),
      ],
    ]),
  );
}
