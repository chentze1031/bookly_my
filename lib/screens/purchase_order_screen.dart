import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../constants.dart';
import '../accounting_models.dart';
import '../state/app_state.dart';
import '../state/accounting_state.dart';
import '../state/sub_state.dart';
import '../services/inventory_service.dart';
import '../utils.dart';
import '../utils/purchase_order_pdf.dart';
import '../services/db_service.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart' show DashedBtn, SmBtn, SheetHandle, EmptyHint;
import 'inventory_screen.dart' show showInventoryPicker;

// ═══════════════════════════════════════════════════════════════════════════════
// PURCHASE ORDER (Phase 3 Task #18, Pro)
// Receiving a PO adds stock for line items linked to inventory (inv_id).
// ═══════════════════════════════════════════════════════════════════════════════

class PurchaseOrderHistoryScreen extends StatefulWidget {
  const PurchaseOrderHistoryScreen({super.key});
  @override State<PurchaseOrderHistoryScreen> createState() => _PoHistState();
}

class _PoHistState extends State<PurchaseOrderHistoryScreen> {
  List<Map<String, dynamic>> _pos = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final list = await context.read<AppState>().loadPurchaseOrders();
    if (mounted) setState(() { _pos = list; _loading = false; });
  }

  static double _total(Map<String, dynamic> po) =>
      (po['items'] as List? ?? []).fold<double>(0, (s, r) {
        final qty = double.tryParse(r['qty'] ?? '1') ?? 1;
        final price = double.tryParse(r['price'] ?? '0') ?? 0;
        return s + qty * price;
      });

  Future<void> _exportPdf(Map<String, dynamic> po) async {
    final app = context.read<AppState>();
    try {
      final items = (po['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final bytes = await generatePurchaseOrderPdf(
        co: app.settings,
        supplier: Map<String, dynamic>.from(po['supplier'] ?? {}),
        rows: items, poNo: po['poNo'] ?? '', poDate: po['poDate'] ?? '',
        logoBase64: app.settings.logoBase64,
        notes: (po['notes'] ?? '').isNotEmpty ? po['notes'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (po['poNo'] ?? 'po').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/PurchaseOrder_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Purchase Order ${po['poNo']}');
      if (mounted) context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  // Receive into stock: add qty for linked items, mark received (once).
  Future<void> _receive(Map<String, dynamic> po) async {
    if (po['status'] == 'received') return;
    final app = context.read<AppState>();
    final inv = context.read<InventoryState>();
    int linked = 0;
    for (final r in (po['items'] as List? ?? [])) {
      final invId = int.tryParse((r['inv_id'] ?? '').toString());
      final qty   = double.tryParse((r['qty'] ?? '0').toString()) ?? 0;
      if (invId != null && qty > 0) {
        try { await inv.applyMovement(invId, 'purchase', qty, note: 'PO ${po['poNo']}'); linked++; } catch (_) {}
      }
    }
    await app.markPurchaseOrderStatus(po['poNo'] ?? '', 'received');
    await _load();
    if (mounted) {
      final lang = app.settings.lang;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(lang, 'Received · $linked item(s) added to stock', '已收货 · $linked 项入库', 'Diterima · $linked item ditambah ke stok')),
        backgroundColor: kDark, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _delete(String poNo) async {
    await context.read<AppState>().deletePurchaseOrder(poNo);
    _load();
  }

  void _confirmDelete(String poNo) {
    showDialog(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Delete Purchase Order?'),
      content: Text('Delete $poNo? (Received stock is not reversed.)'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(dctx); _delete(poNo); },
          child: Text('Delete', style: TextStyle(color: kRed))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final t    = L10n(lang);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(t.poHistory),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [IconButton(icon: Icon(Icons.add, color: kText), onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderSheet()));
          _load();
        })],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _pos.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📦', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(tr(lang, 'No purchase orders yet', '还没有采购单', 'Belum ada pesanan belian'), style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderSheet()));
                  _load();
                },
                icon: const Icon(Icons.add), label: Text(t.newPurchaseOrder),
                style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ]))
          : RefreshIndicator(onRefresh: _load, child: ListView.builder(
              padding: const EdgeInsets.all(16), itemCount: _pos.length,
              itemBuilder: (_, i) => _PoCard(
                po: _pos[i], total: _total(_pos[i]), lang: lang,
                onExport: () => _exportPdf(_pos[i]),
                onReceive: _pos[i]['status'] == 'received' ? null : () => _receive(_pos[i]),
                onDelete: () => _confirmDelete(_pos[i]['poNo'] ?? ''),
                onEdit: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PurchaseOrderSheet(existing: _pos[i])));
                  _load();
                },
              ),
            )),
    );
  }
}

class _PoCard extends StatelessWidget {
  final Map<String, dynamic> po;
  final double total;
  final String lang;
  final VoidCallback? onExport, onReceive, onDelete, onEdit;
  const _PoCard({required this.po, required this.total, required this.lang,
    this.onExport, this.onReceive, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t = L10n(lang);
    final supplier = po['supplier'] as Map? ?? {};
    final items = (po['items'] as List? ?? []);
    final received = po['status'] == 'received';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.vertical(top: Radius.circular(14)), border: Border(bottom: BorderSide(color: kBorder))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(po['poNo'] ?? '—', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
              Text(po['poDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (received ? kGreen : const Color(0xFFD97706)).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: (received ? kGreen : const Color(0xFFD97706)).withOpacity(0.3)),
              ),
              child: Text(received ? t.poReceived : t.poOrdered,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: received ? kGreen : const Color(0xFFD97706))),
            ),
            const SizedBox(width: 10),
            Text(fmtMYR(total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((supplier['name'] ?? '').toString().isNotEmpty)
              Row(children: [const Text('🏭 ', style: TextStyle(fontSize: 13)),
                Text(supplier['name'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))]),
            const SizedBox(height: 4),
            Text('${items.length} item${items.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text(tr(lang, 'Edit', '编辑', 'Sunting')),
                style: OutlinedButton.styleFrom(foregroundColor: kText, side: BorderSide(color: kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: onExport, icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                label: Text(tr(lang, 'PDF', '导出', 'PDF')),
                style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlueBd), backgroundColor: kBlueBg,
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: onReceive,
                icon: Icon(received ? Icons.check_circle_outline : Icons.inventory_2_outlined, size: 14),
                label: Text(received ? tr(lang, 'Done', '已收', 'Selesai') : t.receiveStock),
                style: OutlinedButton.styleFrom(
                  foregroundColor: received ? kMuted : kGreen,
                  side: BorderSide(color: received ? kBorder : kGreenBd),
                  backgroundColor: received ? kSurface : kGreenBg,
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              GestureDetector(onTap: onDelete, child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kRedBg, border: Border.all(color: kRedBd), borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.delete_outline, size: 16, color: kRed))),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PURCHASE ORDER SHEET (create / edit)
// ═══════════════════════════════════════════════════════════════════════════════
class PurchaseOrderSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const PurchaseOrderSheet({super.key, this.existing});
  @override State<PurchaseOrderSheet> createState() => _PoSheetState();
}

class _PoSheetState extends State<PurchaseOrderSheet> {
  String _poNo = '';
  String _poDate = nowISO();
  String _notes = '';
  bool _saving = false, _sharing = false;
  Map<String, dynamic> _supplier = {'name': ''};
  String _status = 'ordered';

  final List<Map<String, String>> _items = [
    {'desc': '', 'qty': '1', 'price': '', 'inv_id': ''},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final po = widget.existing!;
      _poNo = po['poNo'] ?? ''; _poDate = po['poDate'] ?? nowISO();
      _notes = po['notes'] ?? '';
      _status = po['status'] ?? 'ordered'; // preserve received status on edit
      _supplier = Map<String, dynamic>.from(po['supplier'] ?? {'name': ''});
      if (po['items'] != null) {
        _items..clear()..addAll((po['items'] as List).map((e) => Map<String, String>.from(e)));
      }
    } else {
      DbService.nextPoNo().then((no) { if (mounted) setState(() => _poNo = no); });
    }
  }

  double get _total => _items.fold(0, (s, r) {
    final qty = double.tryParse(r['qty'] ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    return s + qty * price;
  });

  Future<void> _pickSupplier() async {
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccountingState>(),
        child: SupplierManagerScreen(onSelect: (s) => setState(() => _supplier = {
          'id': s.id, 'name': s.name, 'regNo': s.regNo,
          'address': s.address, 'phone': s.phone, 'email': s.email,
        })),
      ),
    );
  }

  Future<void> _linkInventory(int idx) async {
    final item = await showInventoryPicker(context);
    if (item == null) return;
    setState(() {
      _items[idx] = {
        'desc': item.name, 'qty': _items[idx]['qty'] ?? '1',
        'price': item.costPrice.toString(), 'inv_id': item.id.toString(),
      };
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_supplier['name'] == null || (_supplier['name'] as String).trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enter a supplier'), backgroundColor: kRed));
        return;
      }
      await context.read<AppState>().savePurchaseOrder(
        poNo: _poNo, poDate: _poDate, supplier: _supplier,
        items: List<Map<String, String>>.from(_items), notes: _notes,
        status: _status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$_poNo saved'), backgroundColor: kDark, behavior: SnackBarBehavior.floating));
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      }
    } finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final app = context.read<AppState>();
      final bytes = await generatePurchaseOrderPdf(
        co: app.settings, supplier: _supplier,
        rows: List<Map<String, String>>.from(_items),
        poNo: _poNo, poDate: _poDate, logoBase64: app.settings.logoBase64,
        notes: _notes.isNotEmpty ? _notes : null,
      );
      final dir = await getTemporaryDirectory();
      final safe = _poNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/PurchaseOrder_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: 'Purchase Order $_poNo');
      if (mounted) { context.read<SubState>().onShareAction(); await _save(); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    } finally { if (mounted) setState(() => _sharing = false); }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final t = L10n(lang);
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: kMuted), onPressed: () => Navigator.pop(context)),
        title: Row(children: [const Text('📦 ', style: TextStyle(fontSize: 20)),
          Text(t.purchaseOrder, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText))]),
        actions: [
          SmBtn(label: _saving ? '…' : '💾 ${t.save}', color: kGreenBg, borderColor: kGreenBd, textColor: kGreen, onTap: _saving ? () {} : _save),
          const SizedBox(width: 8),
          SmBtn(label: _sharing ? '…' : t.sharePrint, color: kDark, borderColor: kDark, textColor: Colors.white, onTap: _sharing ? () {} : _share),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _Section(title: tr(lang, 'Order Details', '采购单信息', 'Butiran Pesanan'), child: Column(children: [
            Row(children: [
              Expanded(child: FieldInput(label: t.poNo, value: _poNo, onChanged: (v) => setState(() => _poNo = v))),
              const SizedBox(width: 10),
              Expanded(child: FieldInput(label: t.poDate, value: _poDate, keyboard: TextInputType.datetime, onChanged: (v) => setState(() => _poDate = v))),
            ]),
            // Supplier
            Align(alignment: Alignment.centerLeft, child: Text(tr(lang, 'SUPPLIER', '供应商', 'PEMBEKAL'),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5))),
            const SizedBox(height: 6),
            if ((_supplier['name'] ?? '').toString().trim().isEmpty)
              DashedBtn(label: '🏭 ${tr(lang, 'Select Supplier', '选择供应商', 'Pilih Pembekal')}', onTap: _pickSupplier)
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((_supplier['name'] ?? '') as String,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                    if (((_supplier['phone'] ?? '') as String).isNotEmpty)
                      Text(_supplier['phone'] as String, style: const TextStyle(fontSize: 11, color: kMuted)),
                    if (((_supplier['address'] ?? '') as String).isNotEmpty)
                      Text(_supplier['address'] as String, style: const TextStyle(fontSize: 11, color: kMuted),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ])),
                  SmBtn(label: tr(lang, 'Change', '更改', 'Tukar'), onTap: _pickSupplier),
                ]),
              ),
            const SizedBox(height: 6),
          ])),
          const SizedBox(height: 12),

          _Section(title: t.items, child: Column(children: [
            ..._items.asMap().entries.map((e) => _PoItemRow(
              index: e.key, item: e.value, lang: lang,
              onChanged: (u) => setState(() => _items[e.key] = u),
              onLink: () => _linkInventory(e.key),
              onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
            )),
            const SizedBox(height: 8),
            DashedBtn(label: '+ ${t.addLine}', onTap: () => setState(() => _items.add({'desc': '', 'qty': '1', 'price': '', 'inv_id': ''}))),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(tr(lang, 'TOTAL', '总计', 'JUMLAH'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
              Text(fmtMYR(_total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kText)),
            ]),
          ])),
          const SizedBox(height: 12),

          _Section(title: t.notes, child: FieldInput(label: t.notes, value: _notes, multiline: true,
            onChanged: (v) => setState(() => _notes = v))),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PoItemRow extends StatelessWidget {
  final int index;
  final Map<String, String> item;
  final String lang;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback onLink;
  final VoidCallback? onRemove;
  const _PoItemRow({required this.index, required this.item, required this.lang,
    required this.onChanged, required this.onLink, this.onRemove});

  void _up(String k, String v) => onChanged(Map<String, String>.from(item)..[k] = v);

  @override
  Widget build(BuildContext context) {
    final t = L10n(lang);
    final linked = (item['inv_id'] ?? '').isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kMuted)),
          const Spacer(),
          GestureDetector(onTap: onLink, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: linked ? kGreenBg : kSurface, border: Border.all(color: linked ? kGreenBd : kBorder), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(linked ? Icons.link : Icons.add_link, size: 13, color: linked ? kGreen : kMuted),
              const SizedBox(width: 4),
              Text(linked ? tr(lang, 'Linked', '已关联库存', 'Dipaut') : tr(lang, 'Link stock', '关联库存', 'Paut stok'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: linked ? kGreen : kMuted)),
            ]),
          )),
          if (onRemove != null) ...[const SizedBox(width: 8),
            GestureDetector(onTap: onRemove, child: Icon(Icons.remove_circle_outline, size: 18, color: kRed))],
        ]),
        const SizedBox(height: 6),
        FieldInput(label: t.description2, value: item['desc'] ?? '', onChanged: (v) => _up('desc', v)),
        Row(children: [
          Expanded(child: FieldInput(label: t.qty, value: item['qty'] ?? '1', keyboard: TextInputType.number, onChanged: (v) => _up('qty', v))),
          const SizedBox(width: 8),
          Expanded(child: FieldInput(label: tr(lang, 'Unit Cost', '成本价', 'Harga Kos'), value: item['price'] ?? '', keyboard: TextInputType.number, onChanged: (v) => _up('price', v))),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUPPLIER MANAGER (select → add → fill details), mirrors the customer/employee
// manager. Backed by AccountingState.suppliers.
// ═══════════════════════════════════════════════════════════════════════════════
class SupplierManagerScreen extends StatefulWidget {
  final void Function(Supplier)? onSelect;
  const SupplierManagerScreen({super.key, this.onSelect});
  @override State<SupplierManagerScreen> createState() => _SuppMgrState();
}

class _SuppMgrState extends State<SupplierManagerScreen> {
  Supplier? _editing;

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountingState>();
    final lang = context.read<AppState>().settings.lang;

    if (_editing != null) {
      return _SuppEditForm(
        supplier: _editing!, lang: lang,
        onSave: (s) async { await acc.saveSupplier(s); if (mounted) setState(() => _editing = null); },
        onCancel: () => setState(() => _editing = null),
      );
    }

    return Container(
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88 - MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        SheetHandle(title: tr(lang, 'Suppliers', '供应商管理', 'Pembekal')),
        Expanded(child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            DashedBtn(label: '+ ${tr(lang, 'New Supplier', '新增供应商', 'Pembekal Baharu')}',
              onTap: () => setState(() => _editing = const Supplier(id: 0, name: ''))),
            const SizedBox(height: 10),
            if (acc.suppliers.isEmpty)
              EmptyHint(icon: '🏭', label: tr(lang, 'No suppliers yet', '暂无供应商', 'Belum ada pembekal')),
            ...acc.suppliers.map((s) => _SuppCard(
              supplier: s,
              onSelect: widget.onSelect != null
                ? () { widget.onSelect!(s); Navigator.pop(context); } : null,
              onEdit: () => setState(() => _editing = s),
              onDelete: () => acc.deleteSupplier(s.id),
            )),
          ],
        )),
      ]),
    );
  }
}

class _SuppCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback? onSelect, onEdit, onDelete;
  const _SuppCard({required this.supplier, this.onSelect, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(supplier.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
        if (supplier.regNo.isNotEmpty) Text('Reg: ${supplier.regNo}', style: const TextStyle(fontSize: 11, color: kMuted)),
        if (supplier.phone.isNotEmpty) Text(supplier.phone, style: const TextStyle(fontSize: 11, color: kMuted)),
      ])),
      if (onSelect != null) ...[
        SmBtn(label: 'Select', color: kDark, textColor: Colors.white, onTap: onSelect!),
        const SizedBox(width: 6),
      ],
      SmBtn(label: 'Edit', onTap: onEdit ?? () {}),
      const SizedBox(width: 6),
      GestureDetector(onTap: onDelete, child: Icon(Icons.delete_outline, color: kRed, size: 22)),
    ]),
  );
}

class _SuppEditForm extends StatefulWidget {
  final Supplier supplier;
  final String lang;
  final Future<void> Function(Supplier) onSave;
  final VoidCallback onCancel;
  const _SuppEditForm({required this.supplier, required this.lang, required this.onSave, required this.onCancel});
  @override State<_SuppEditForm> createState() => _SuppEditFormState();
}

class _SuppEditFormState extends State<_SuppEditForm> {
  late Supplier _s;
  bool _saving = false;
  @override void initState() { super.initState(); _s = widget.supplier; }
  void _u(Supplier s) => setState(() => _s = s);

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Column(children: [
          SheetHandle(title: _s.id == 0 ? tr(lang, 'New Supplier', '新增供应商', 'Pembekal Baharu') : tr(lang, 'Supplier', '供应商', 'Pembekal'),
            trailing: TextButton(onPressed: widget.onCancel, child: const Text('← Back'))),
          Expanded(child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: Column(children: [
              FieldInput(label: tr(lang, 'Supplier Name', '供应商名称', 'Nama Pembekal'), value: _s.name, onChanged: (v) => _u(_s.copyWith(name: v))),
              Row(children: [
                Expanded(child: FieldInput(label: tr(lang, 'Reg No.', '注册号', 'No. Pendaftaran'), value: _s.regNo, onChanged: (v) => _u(_s.copyWith(regNo: v)))),
                const SizedBox(width: 10),
                Expanded(child: FieldInput(label: tr(lang, 'SST Reg No.', 'SST 注册号', 'No. Pendaftaran SST'), value: _s.sstRegNo, onChanged: (v) => _u(_s.copyWith(sstRegNo: v)))),
              ]),
              FieldInput(label: tr(lang, 'Address', '地址', 'Alamat'), value: _s.address, multiline: true, onChanged: (v) => _u(_s.copyWith(address: v))),
              Row(children: [
                Expanded(child: FieldInput(label: tr(lang, 'Phone', '电话', 'Telefon'), value: _s.phone, keyboard: TextInputType.phone, onChanged: (v) => _u(_s.copyWith(phone: v)))),
                const SizedBox(width: 10),
                Expanded(child: FieldInput(label: tr(lang, 'Email', '邮箱', 'E-mel'), value: _s.email, keyboard: TextInputType.emailAddress, onChanged: (v) => _u(_s.copyWith(email: v)))),
              ]),
              Row(children: [
                Expanded(child: FieldInput(label: tr(lang, 'Bank', '银行', 'Bank'), value: _s.bankName ?? '', onChanged: (v) => _u(_s.copyWith(bankName: v)))),
                const SizedBox(width: 10),
                Expanded(child: FieldInput(label: tr(lang, 'Account No.', '账号', 'No. Akaun'), value: _s.bankAcct ?? '', onChanged: (v) => _u(_s.copyWith(bankAcct: v)))),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _saving || _s.name.trim().isEmpty ? null : () async {
                  setState(() => _saving = true);
                  await widget.onSave(_s);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDark, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_saving ? '…' : tr(lang, 'Save Supplier', '保存供应商', 'Simpan Pembekal'), style: const TextStyle(fontWeight: FontWeight.w700)),
              )),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title; final Widget child;
  const _Section({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kMuted, letterSpacing: 0.5))),
      Padding(padding: const EdgeInsets.all(14), child: child),
    ]),
  );
}
