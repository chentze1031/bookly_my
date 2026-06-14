import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../utils/delivery_order_pdf.dart';
import '../services/db_service.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart' show DashedBtn, SmBtn, CustomerManagerScreen;

// ═══════════════════════════════════════════════════════════════════════════════
// DELIVERY ORDER HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class DeliveryOrderHistoryScreen extends StatefulWidget {
  const DeliveryOrderHistoryScreen({super.key});
  @override State<DeliveryOrderHistoryScreen> createState() => _DoHistState();
}

class _DoHistState extends State<DeliveryOrderHistoryScreen> {
  List<Map<String, dynamic>> _dos = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadDeliveryOrders();
    if (mounted) setState(() { _dos = list; _loading = false; });
  }

  static double _totalQty(Map<String, dynamic> d) {
    return (d['items'] as List? ?? []).fold<double>(
        0, (s, r) => s + (double.tryParse(r['qty'] ?? '0') ?? 0));
  }

  Future<void> _exportPdf(Map<String, dynamic> d) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(d['customer'] ?? {}));
      final items = (d['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final bytes = await generateDeliveryOrderPdf(
        co:          app.settings,
        customer:    customer,
        rows:        items,
        doNo:        d['doNo'] ?? '',
        doDate:      d['doDate'] ?? '',
        refInvNo:    (d['refInvNo'] ?? '').isNotEmpty ? d['refInvNo'] : null,
        logoBase64:  app.settings.logoBase64,
        notes:       (d['notes'] ?? '').isNotEmpty ? d['notes'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (d['doNo'] ?? 'do').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/DeliveryOrder_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Delivery Order ${d['doNo']}');
      context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(String doNo) async {
    await context.read<AppState>().deleteDeliveryOrder(doNo);
    _load();
  }

  void _confirmDelete(String doNo) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Delivery Order?'),
      content: Text('Delete $doNo? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () { Navigator.pop(context); _delete(doNo); },
          child: const Text('Delete', style: TextStyle(color: kRed)),
        ),
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
        title: Text(t.doHistory),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kText),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DeliveryOrderSheet()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _dos.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🚚', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(lang == 'zh' ? '还没有送货单' : 'No delivery orders yet',
                  style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DeliveryOrderSheet()));
                  _load();
                },
                icon: const Icon(Icons.add),
                label: Text(t.newDeliveryOrder),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _dos.length,
                itemBuilder: (_, i) {
                  final d = _dos[i];
                  return _DoCard(
                    d: d,
                    totalQty: _totalQty(d),
                    lang: lang,
                    onExport: () => _exportPdf(d),
                    onDelete: () => _confirmDelete(d['doNo'] ?? ''),
                    onEdit: () async {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DeliveryOrderSheet(existing: d),
                      ));
                      _load();
                    },
                  );
                },
              ),
            ),
    );
  }
}

// ── Delivery order list card ────────────────────────────────────────────────────
class _DoCard extends StatelessWidget {
  final Map<String, dynamic> d;
  final double totalQty;
  final String lang;
  final VoidCallback? onExport, onDelete, onEdit;
  const _DoCard({required this.d, required this.totalQty, required this.lang,
      this.onExport, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final customer = d['customer'] as Map? ?? {};
    final items    = (d['items'] as List? ?? []);
    final qtyStr   = totalQty == totalQty.truncate()
        ? totalQty.toStringAsFixed(0) : totalQty.toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kBorder)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['doNo'] ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
              Text(d['doDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${lang == 'zh' ? '总数量' : 'Total Qty'}: $qtyStr',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: kText)),
              if ((d['refInvNo'] ?? '').isNotEmpty)
                Text('← ${d['refInvNo']}', style: const TextStyle(fontSize: 10, color: kBlue)),
            ]),
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((customer['name'] ?? '').isNotEmpty)
              Row(children: [
                const Text('🚚 ', style: TextStyle(fontSize: 13)),
                Text(customer['name'] ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
              ]),
            const SizedBox(height: 4),
            Text('${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: Text(lang == 'zh' ? '编辑' : 'Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kText, side: const BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: Text(lang == 'zh' ? '导出' : 'PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kBlue, side: const BorderSide(color: kBlueBd),
                    backgroundColor: kBlueBg,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: kRedBg, border: Border.all(color: kRedBd),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.delete_outline, size: 16, color: kRed),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELIVERY ORDER SHEET (Create / Edit / from-invoice)
// ═══════════════════════════════════════════════════════════════════════════════

class DeliveryOrderSheet extends StatefulWidget {
  final Map<String, dynamic>? existing; // edit mode
  // Pre-fill from invoice conversion
  final Customer?                  initCustomer;
  final List<Map<String, String>>? initItems;
  final String?                    refInvNo;

  const DeliveryOrderSheet({
    super.key,
    this.existing,
    this.initCustomer,
    this.initItems,
    this.refInvNo,
  });

  @override State<DeliveryOrderSheet> createState() => _DoSheetState();
}

class _DoSheetState extends State<DeliveryOrderSheet> {
  String _doNo   = '';
  String _doDate = nowISO();
  String _notes  = '';
  String _refInvNo = '';
  String _driver = '';
  bool   _saving  = false;
  bool   _sharing = false;

  Customer _customer = Customer(id: 0, name: '');

  final List<Map<String, String>> _items = [
    {'desc': '', 'qty': '1', 'note': ''},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final d = widget.existing!;
      _doNo     = d['doNo'] ?? '';
      _doDate   = d['doDate'] ?? nowISO();
      _notes    = d['notes'] ?? '';
      _refInvNo = d['refInvNo'] ?? '';
      _driver   = d['driver'] ?? '';
      if (d['customer'] != null) {
        _customer = Customer.fromMap(Map<String, dynamic>.from(d['customer']));
      }
      if (d['items'] != null) {
        _items
          ..clear()
          ..addAll((d['items'] as List).map((e) => Map<String, String>.from(e)));
      }
    } else {
      if (widget.initCustomer != null) _customer = widget.initCustomer!;
      if (widget.refInvNo != null) _refInvNo = widget.refInvNo!;
      if (widget.initItems != null && widget.initItems!.isNotEmpty) {
        _items
          ..clear()
          // keep only desc + qty (+ note) — delivery order has no prices
          ..addAll(widget.initItems!.map((e) => {
                'desc': e['desc'] ?? '',
                'qty':  e['qty']  ?? '1',
                'note': e['note'] ?? '',
              }));
      }
      DbService.nextDoNo().then((no) {
        if (mounted) setState(() => _doNo = no);
      });
    }
  }

  double get _totalQty =>
      _items.fold(0, (s, r) => s + (double.tryParse(r['qty'] ?? '0') ?? 0));

  // One-click: pick a saved invoice → fills ref no. + customer + items (qty only)
  Future<void> _pickInvoice() async {
    final lang     = context.read<AppState>().settings.lang;
    final invoices = await context.read<AppState>().loadInvoices();
    if (!mounted) return;
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n(lang).noInvoices)));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(children: [
              Text(L10n(lang).selectInvoice,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: const Icon(Icons.close, size: 20, color: kMuted),
              ),
            ]),
          ),
          const Divider(height: 1, color: kBorder),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
              itemBuilder: (_, i) {
                final inv  = invoices[i];
                final cust = inv['customer'] as Map? ?? {};
                return ListTile(
                  title: Text(inv['invNo'] ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                  subtitle: Text(
                    '${cust['name'] ?? ''}${(inv['invDate'] ?? '').isNotEmpty ? ' · ${inv['invDate']}' : ''}',
                    style: const TextStyle(fontSize: 12, color: kMuted)),
                  trailing: const Icon(Icons.chevron_right, color: kMuted),
                  onTap: () { _applyInvoice(inv); Navigator.pop(ctx); },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _applyInvoice(Map<String, dynamic> inv) {
    setState(() {
      _refInvNo = inv['invNo'] ?? '';
      if (inv['customer'] != null) {
        _customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer']));
      }
      final items = (inv['items'] as List? ?? []).map((e) => {
        'desc': (e['desc'] ?? '').toString(),
        'qty':  (e['qty']  ?? '1').toString(),
        'note': (e['note'] ?? '').toString(),
      }).toList();
      if (items.isNotEmpty) { _items..clear()..addAll(items); }
    });
  }

  Future<void> _save({String status = 'draft'}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveDeliveryOrder(
        doNo:     _doNo,
        doDate:   _doDate,
        customer: _customer,
        items:    List<Map<String, String>>.from(_items),
        notes:    _notes,
        refInvNo: _refInvNo,
        driver:   _driver,
        status:   status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text('$_doNo saved'),
          ]),
          backgroundColor: kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final app      = context.read<AppState>();
      final pdfBytes = await generateDeliveryOrderPdf(
        co:         app.settings,
        customer:   _customer,
        rows:       List<Map<String, String>>.from(_items),
        doNo:       _doNo,
        doDate:     _doDate,
        refInvNo:   _refInvNo.isNotEmpty ? _refInvNo : null,
        driver:     _driver.isNotEmpty ? _driver : null,
        logoBase64: app.settings.logoBase64,
        notes:      _notes.isNotEmpty ? _notes : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = _doNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/DeliveryOrder_$safe.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Delivery Order $_doNo');
      context.read<SubState>().onShareAction();
      if (mounted) await _save(status: 'delivered');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;
    final t    = L10n(lang);

    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: kMuted),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const Text('🚚 ', style: TextStyle(fontSize: 20)),
          Text(t.deliveryOrder,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
        ]),
        actions: [
          SmBtn(
            label: _saving ? (lang == 'zh' ? '保存中…' : 'Saving…') : '💾 ${t.save}',
            color: kGreenBg, borderColor: kGreenBd, textColor: kGreen,
            onTap: _saving ? () {} : () => _save(),
          ),
          const SizedBox(width: 8),
          // ── Share button (same size as Save, no icon) ─────────────
          SmBtn(
            label: _sharing ? (lang == 'zh' ? '分享中…' : 'Sharing…') : t.sharePrint,
            color: kDark, borderColor: kDark, textColor: Colors.white,
            onTap: _sharing ? () {} : _share,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [

          // ── Delivery details ──────────────────────────────────────────────
          _SectionBox(
            title: lang == 'zh' ? '送货单信息' : 'Delivery Details',
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                FieldInput(
                  label: t.doNo, value: _doNo,
                  onChanged: (v) => setState(() => _doNo = v),
                ),
                Row(children: [
                  Expanded(child: FieldInput(
                    label: t.doDate, value: _doDate,
                    keyboard: TextInputType.datetime,
                    onChanged: (v) => setState(() => _doDate = v),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(
                    label: t.deliveryDriver, value: _driver,
                    placeholder: lang == 'zh' ? '司机姓名' : 'Driver name',
                    onChanged: (v) => setState(() => _driver = v),
                  )),
                ]),
                // ── One-click invoice picker ────────────────────────────────
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.refInvoice.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: kMuted, letterSpacing: 0.5)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _pickInvoice,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      color: kBg,
                      border: Border.all(color: kBorder, width: 1.5),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(children: [
                      const Icon(Icons.receipt_long_outlined, size: 18, color: kBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _refInvNo.isNotEmpty
                              ? _refInvNo
                              : (lang == 'zh' ? '点击选择发票（带出客户+明细）'
                                              : 'Tap to select invoice'),
                          style: TextStyle(fontSize: 14,
                              color: _refInvNo.isNotEmpty ? kText : kMuted,
                              fontWeight: _refInvNo.isNotEmpty ? FontWeight.w700 : FontWeight.normal),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_refInvNo.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _refInvNo = ''),
                          child: const Icon(Icons.close, size: 16, color: kMuted),
                        )
                      else
                        const Icon(Icons.chevron_right, size: 18, color: kMuted),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // ── Customer (deliver to) ─────────────────────────────────────────
          _SectionBox(
            title: t.deliverTo,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_customer.id == 0 || _customer.name.isEmpty)
                  DashedBtn(
                    label: '🚚 ${lang == 'zh' ? '选择客户' : 'Select Customer'}',
                    onTap: () => showModalBottomSheet(
                      context: context, isScrollControlled: true,
                      builder: (_) => CustomerManagerScreen(
                        onSelect: (c) => setState(() => _customer = c),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kBg, border: Border.all(color: kBorder),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_customer.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                        if (_customer.phone.isNotEmpty)
                          Text(_customer.phone, style: const TextStyle(fontSize: 11, color: kMuted)),
                        if (_customer.address.isNotEmpty)
                          Text(_customer.address, style: const TextStyle(fontSize: 11, color: kMuted),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                      ])),
                      SmBtn(
                        label: lang == 'zh' ? '更改' : 'Change',
                        onTap: () => showModalBottomSheet(
                          context: context, isScrollControlled: true,
                          builder: (_) => CustomerManagerScreen(
                            onSelect: (c) => setState(() => _customer = c),
                          ),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // ── Line items (qty only) ─────────────────────────────────────────
          _SectionBox(
            title: t.items,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ..._items.asMap().entries.map((e) => _DoItemRow(
                  index:     e.key,
                  item:      e.value,
                  lang:      lang,
                  onChanged: (updated) => setState(() => _items[e.key] = updated),
                  onRemove:  _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
                )),
                const SizedBox(height: 8),
                DashedBtn(
                  label: '+ ${t.addLine}',
                  onTap: () => setState(() => _items.add({'desc': '', 'qty': '1', 'note': ''})),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(lang == 'zh' ? '总数量' : 'Total Quantity',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
                  Text(_totalQty == _totalQty.truncate()
                          ? _totalQty.toStringAsFixed(0) : _totalQty.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kText)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // ── Notes ─────────────────────────────────────────────────────────
          _SectionBox(
            title: t.notes,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: FieldInput(
                label: t.notes, value: _notes, multiline: true,
                placeholder: lang == 'zh'
                    ? '如：货物已点收无误。'
                    : 'e.g. Goods received in good order.',
                onChanged: (v) => setState(() => _notes = v),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── DO item row (description + quantity only) ───────────────────────────────────
class _DoItemRow extends StatelessWidget {
  final int index;
  final Map<String, String> item;
  final String lang;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback? onRemove;
  const _DoItemRow({required this.index, required this.item, required this.lang,
      required this.onChanged, this.onRemove});

  void _up(String key, String val) =>
      onChanged(Map<String, String>.from(item)..[key] = val);

  @override
  Widget build(BuildContext context) {
    final t = L10n(lang);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${index + 1}.',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kMuted)),
          const Spacer(),
          if (onRemove != null)
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.remove_circle_outline, size: 18, color: kRed),
            ),
        ]),
        const SizedBox(height: 6),
        FieldInput(
          label: t.description2, value: item['desc'] ?? '',
          onChanged: (v) => _up('desc', v),
        ),
        Row(children: [
          Expanded(child: FieldInput(
            label: t.qty, value: item['qty'] ?? '1',
            keyboard: TextInputType.number,
            onChanged: (v) => _up('qty', v),
          )),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: FieldInput(
            label: lang == 'zh' ? '备注' : 'Note', value: item['note'] ?? '',
            onChanged: (v) => _up('note', v),
          )),
        ]),
      ]),
    );
  }
}

// ── Section box ───────────────────────────────────────────────────────────────
class _SectionBox extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionBox({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kSurface, border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Text(title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                color: kMuted, letterSpacing: 0.5)),
      ),
      child,
    ]),
  );
}
