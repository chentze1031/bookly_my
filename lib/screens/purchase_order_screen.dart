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
import 'invoice_screen.dart' show DashedBtn, SmBtn;
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
      final zh = app.settings.lang == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(zh ? '已收货 · $linked 项入库' : 'Received · $linked item(s) added to stock'),
        backgroundColor: kDark, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _delete(String poNo) async {
    await context.read<AppState>().deletePurchaseOrder(poNo);
    _load();
  }

  void _confirmDelete(String poNo) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Purchase Order?'),
      content: Text('Delete $poNo? (Received stock is not reversed.)'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(context); _delete(poNo); },
          child: const Text('Delete', style: TextStyle(color: kRed))),
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
        actions: [IconButton(icon: const Icon(Icons.add, color: kText), onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseOrderSheet()));
          _load();
        })],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _pos.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📦', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(lang == 'zh' ? '还没有采购单' : 'No purchase orders yet', style: const TextStyle(color: kMuted, fontSize: 15)),
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
          decoration: const BoxDecoration(color: kBg, borderRadius: BorderRadius.vertical(top: Radius.circular(14)), border: Border(bottom: BorderSide(color: kBorder))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(po['poNo'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
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
            Text(fmtMYR(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((supplier['name'] ?? '').toString().isNotEmpty)
              Row(children: [const Text('🏭 ', style: TextStyle(fontSize: 13)),
                Text(supplier['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))]),
            const SizedBox(height: 4),
            Text('${items.length} item${items.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text(lang == 'zh' ? '编辑' : 'Edit'),
                style: OutlinedButton.styleFrom(foregroundColor: kText, side: const BorderSide(color: kBorder),
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: onExport, icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                label: Text(lang == 'zh' ? '导出' : 'PDF'),
                style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlueBd), backgroundColor: kBlueBg,
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(
                onPressed: onReceive,
                icon: Icon(received ? Icons.check_circle_outline : Icons.inventory_2_outlined, size: 14),
                label: Text(received ? (lang == 'zh' ? '已收' : 'Done') : t.receiveStock),
                style: OutlinedButton.styleFrom(
                  foregroundColor: received ? kMuted : kGreen,
                  side: BorderSide(color: received ? kBorder : kGreenBd),
                  backgroundColor: received ? kSurface : kGreenBg,
                  padding: const EdgeInsets.symmetric(vertical: 7), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))))),
              const SizedBox(width: 8),
              GestureDetector(onTap: onDelete, child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kRedBg, border: Border.all(color: kRedBd), borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.delete_outline, size: 16, color: kRed))),
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
    final suppliers = context.read<AccountingState>().suppliers;
    final lang = context.read<AppState>().settings.lang;
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(lang == 'zh' ? '请先在账务→供应商添加供应商，或直接手填名称' : 'Add suppliers in Accounting, or type a name')));
      return;
    }
    final picked = await showModalBottomSheet<Supplier>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 16, 8), child: Row(children: [
            Text(lang == 'zh' ? '选择供应商' : 'Select Supplier', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, size: 20, color: kMuted)),
          ])),
          const Divider(height: 1, color: kBorder),
          Flexible(child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4), itemCount: suppliers.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
            itemBuilder: (_, i) => ListTile(
              title: Text(suppliers[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
              subtitle: suppliers[i].phone.isNotEmpty ? Text(suppliers[i].phone, style: const TextStyle(fontSize: 12, color: kMuted)) : null,
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => Navigator.pop(ctx, suppliers[i]),
            ),
          )),
        ]),
      ),
    );
    if (picked != null) {
      setState(() => _supplier = {
        'id': picked.id, 'name': picked.name, 'regNo': picked.regNo,
        'address': picked.address, 'phone': picked.phone, 'email': picked.email,
      });
    }
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a supplier'), backgroundColor: kRed));
        return;
      }
      await context.read<AppState>().savePurchaseOrder(
        poNo: _poNo, poDate: _poDate, supplier: _supplier,
        items: List<Map<String, String>>.from(_items), notes: _notes,
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
          Text(t.purchaseOrder, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText))]),
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
          _Section(title: lang == 'zh' ? '采购单信息' : 'Order Details', child: Column(children: [
            Row(children: [
              Expanded(child: FieldInput(label: t.poNo, value: _poNo, onChanged: (v) => setState(() => _poNo = v))),
              const SizedBox(width: 10),
              Expanded(child: FieldInput(label: t.poDate, value: _poDate, keyboard: TextInputType.datetime, onChanged: (v) => setState(() => _poDate = v))),
            ]),
            // Supplier
            Align(alignment: Alignment.centerLeft, child: Text((lang == 'zh' ? '供应商' : 'SUPPLIER').toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5))),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: FieldInput(label: lang == 'zh' ? '供应商名称' : 'Supplier name',
                value: (_supplier['name'] ?? '') as String,
                onChanged: (v) => setState(() => _supplier = {..._supplier, 'name': v}))),
            ]),
            Align(alignment: Alignment.centerLeft, child: SmBtn(label: lang == 'zh' ? '从供应商选择' : 'Pick supplier', onTap: _pickSupplier)),
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
              Text(lang == 'zh' ? '总计' : 'TOTAL', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
              Text(fmtMYR(_total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kText)),
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
              Text(linked ? (lang == 'zh' ? '已关联库存' : 'Linked') : (lang == 'zh' ? '关联库存' : 'Link stock'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: linked ? kGreen : kMuted)),
            ]),
          )),
          if (onRemove != null) ...[const SizedBox(width: 8),
            GestureDetector(onTap: onRemove, child: const Icon(Icons.remove_circle_outline, size: 18, color: kRed))],
        ]),
        const SizedBox(height: 6),
        FieldInput(label: t.description2, value: item['desc'] ?? '', onChanged: (v) => _up('desc', v)),
        Row(children: [
          Expanded(child: FieldInput(label: t.qty, value: item['qty'] ?? '1', keyboard: TextInputType.number, onChanged: (v) => _up('qty', v))),
          const SizedBox(width: 8),
          Expanded(child: FieldInput(label: lang == 'zh' ? '成本价' : 'Unit Cost', value: item['price'] ?? '', keyboard: TextInputType.number, onChanged: (v) => _up('price', v))),
        ]),
      ]),
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
