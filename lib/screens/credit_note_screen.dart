import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import '../accounting_models.dart';
import '../state/app_state.dart';
import '../state/accounting_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../utils/credit_note_pdf.dart';
import '../services/db_service.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart' show DashedBtn, SmBtn, CustomerManagerScreen;

// ═══════════════════════════════════════════════════════════════════════════════
// CREDIT NOTE HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class CreditNoteHistoryScreen extends StatefulWidget {
  const CreditNoteHistoryScreen({super.key});
  @override State<CreditNoteHistoryScreen> createState() => _CnHistState();
}

class _CnHistState extends State<CreditNoteHistoryScreen> {
  List<Map<String, dynamic>> _cns = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadCreditNotes();
    if (mounted) setState(() { _cns = list; _loading = false; });
  }

  static double _total(Map<String, dynamic> c) {
    const sstMap = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};
    return (c['items'] as List? ?? []).fold<double>(0, (s, r) {
      final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
      final price = double.tryParse(r['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      return s + net + net * (sstMap[r['sst'] ?? 'none'] ?? 0);
    });
  }

  Future<void> _exportPdf(Map<String, dynamic> c) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(c['customer'] ?? {}));
      final items = (c['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final bytes = await generateCreditNotePdf(
        co:          app.settings,
        customer:    customer,
        rows:        items,
        cnNo:        c['cnNo'] ?? '',
        cnDate:      c['cnDate'] ?? '',
        refInvNo:    (c['refInvNo'] ?? '').isNotEmpty ? c['refInvNo'] : null,
        reason:      (c['reason'] ?? '').isNotEmpty ? c['reason'] : null,
        logoBase64:  app.settings.logoBase64,
        notes:       (c['notes'] ?? '').isNotEmpty ? c['notes'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (c['cnNo'] ?? 'cn').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/CreditNote_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Credit Note ${c['cnNo']}');
      context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(String cnNo) async {
    // Remove the document AND reverse its AR credit memo + GL entry.
    await context.read<AppState>().deleteCreditNote(cnNo);
    final acc = context.read<AccountingState>();
    acc.appState ??= context.read<AppState>();
    await acc.removeCreditNote(cnNo);
    _load();
  }

  void _confirmDelete(String cnNo) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Credit Note?'),
      content: Text('Delete $cnNo? This also reverses the AR adjustment.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () { Navigator.pop(context); _delete(cnNo); },
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
        title: Text(t.cnHistory),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kText),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CreditNoteSheet()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _cns.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🧾', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(lang == 'zh' ? '还没有信用备注' : 'No credit notes yet',
                  style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CreditNoteSheet()));
                  _load();
                },
                icon: const Icon(Icons.add),
                label: Text(t.newCreditNote),
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
                itemCount: _cns.length,
                itemBuilder: (_, i) {
                  final c = _cns[i];
                  return _CnCard(
                    c: c,
                    total: _total(c),
                    lang: lang,
                    onExport: () => _exportPdf(c),
                    onDelete: () => _confirmDelete(c['cnNo'] ?? ''),
                    onEdit: () async {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => CreditNoteSheet(existing: c),
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

// ── Credit note list card ───────────────────────────────────────────────────────
class _CnCard extends StatelessWidget {
  final Map<String, dynamic> c;
  final double total;
  final String lang;
  final VoidCallback? onExport, onDelete, onEdit;
  const _CnCard({required this.c, required this.total, required this.lang,
      this.onExport, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t        = L10n(lang);
    final customer = c['customer'] as Map? ?? {};
    final items    = (c['items'] as List? ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: kRedBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kRedBd)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['cnNo'] ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kRed)),
              Text(c['cnDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            Text('-${fmtMYR(total)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kRed)),
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((customer['name'] ?? '').isNotEmpty)
              Row(children: [
                const Text('👤 ', style: TextStyle(fontSize: 13)),
                Text(customer['name'] ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
              ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('${items.length} item${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: kMuted)),
              if ((c['refInvNo'] ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('← ${c['refInvNo']}', style: const TextStyle(fontSize: 11, color: kBlue)),
              ],
            ]),
            if ((c['reason'] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${t.creditReason}: ${c['reason']}',
                    style: const TextStyle(fontSize: 11, color: kMuted),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 6),
            // AR-reduced badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: kGreenBg, borderRadius: BorderRadius.circular(6),
                border: Border.all(color: kGreenBd),
              ),
              child: Text('✓ ${t.arReduced}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kGreen)),
            ),
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
// CREDIT NOTE SHEET (Create / Edit / from-invoice)
// ═══════════════════════════════════════════════════════════════════════════════

class CreditNoteSheet extends StatefulWidget {
  final Map<String, dynamic>? existing; // edit mode
  // Pre-fill from invoice conversion
  final Customer?                  initCustomer;
  final List<Map<String, String>>? initItems;
  final String?                    refInvNo;

  const CreditNoteSheet({
    super.key,
    this.existing,
    this.initCustomer,
    this.initItems,
    this.refInvNo,
  });

  @override State<CreditNoteSheet> createState() => _CnSheetState();
}

class _CnSheetState extends State<CreditNoteSheet> {
  String _cnNo   = '';
  String _cnDate = nowISO();
  String _reason = '';
  String _refInvNo = '';
  String _notes  = '';
  bool   _saving  = false;
  bool   _sharing = false;

  Customer _customer = Customer(id: 0, name: '');

  final List<Map<String, String>> _items = [
    {'desc': '', 'qty': '1', 'price': '', 'disc': '', 'sst': 'none', 'note': ''},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final c = widget.existing!;
      _cnNo     = c['cnNo'] ?? '';
      _cnDate   = c['cnDate'] ?? nowISO();
      _reason   = c['reason'] ?? '';
      _refInvNo = c['refInvNo'] ?? '';
      _notes    = c['notes'] ?? '';
      if (c['customer'] != null) {
        _customer = Customer.fromMap(Map<String, dynamic>.from(c['customer']));
      }
      if (c['items'] != null) {
        _items
          ..clear()
          ..addAll((c['items'] as List).map((e) => Map<String, String>.from(e)));
      }
    } else {
      if (widget.initCustomer != null) _customer = widget.initCustomer!;
      if (widget.refInvNo != null) _refInvNo = widget.refInvNo!;
      if (widget.initItems != null && widget.initItems!.isNotEmpty) {
        _items
          ..clear()
          ..addAll(widget.initItems!.map((e) => Map<String, String>.from(e)));
      }
      DbService.nextCnNo().then((no) {
        if (mounted) setState(() => _cnNo = no);
      });
    }
  }

  Map<String, double> _calcItem(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    final sub   = qty * price;
    final dAmt  = sub * (disc / 100);
    final net   = sub - dAmt;
    final sst   = net * (sstRates[r['sst'] ?? 'none']?.rate ?? 0);
    return {'net': net, 'sst': sst};
  }

  double get _subtotal => _items.fold(0, (s, r) => s + (_calcItem(r)['net'] ?? 0));
  double get _totalSST => _items.fold(0, (s, r) => s + (_calcItem(r)['sst'] ?? 0));
  double get _grand    => _subtotal + _totalSST;

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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
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
      final items = (inv['items'] as List? ?? [])
          .map((e) => Map<String, String>.from(e)).toList();
      if (items.isNotEmpty) { _items..clear()..addAll(items); }
    });
  }

  // Save the CN document + post/refresh the AR credit memo (negative entry).
  Future<void> _save({String status = 'issued'}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final app = context.read<AppState>();
      await app.saveCreditNote(
        cnNo:     _cnNo,
        cnDate:   _cnDate,
        customer: _customer,
        items:    List<Map<String, String>>.from(_items),
        notes:    _notes,
        reason:   _reason,
        refInvNo: _refInvNo,
        status:   status,
      );

      // ── AR integration: reduce receivable via negative credit memo ──────────
      final acc = context.read<AccountingState>();
      acc.appState ??= app;
      if (_grand > 0 && _customer.name.isNotEmpty) {
        await acc.issueCreditNote(
          cnNo:         _cnNo,
          refInvNo:     _refInvNo,
          customerId:   _customer.id.toString(),
          customerName: _customer.name,
          date:         _cnDate,
          subtotal:     _subtotal,
          sstAmount:    _totalSST,
          total:        _grand,
          reason:       _reason,
          items:        _items.map((r) {
            final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
            final price = double.tryParse(r['price'] ?? '0') ?? 0;
            final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
            final net   = qty * price * (1 - disc / 100);
            return ArInvoiceItem(
              description: r['desc'] ?? '', qty: qty, unitPrice: price, amount: net);
          }).toList(),
        );
      } else {
        await acc.removeCreditNote(_cnNo);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text('$_cnNo saved'),
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
      final pdfBytes = await generateCreditNotePdf(
        co:         app.settings,
        customer:   _customer,
        rows:       List<Map<String, String>>.from(_items),
        cnNo:       _cnNo,
        cnDate:     _cnDate,
        refInvNo:   _refInvNo.isNotEmpty ? _refInvNo : null,
        reason:     _reason.isNotEmpty ? _reason : null,
        logoBase64: app.settings.logoBase64,
        notes:      _notes.isNotEmpty ? _notes : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = _cnNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/CreditNote_$safe.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Credit Note $_cnNo');
      context.read<SubState>().onShareAction();
      if (mounted) await _save(status: 'issued');
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
          const Text('🧾 ', style: TextStyle(fontSize: 20)),
          Text(t.creditNote,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
        ]),
        actions: [
          SmBtn(
            label: _saving ? (lang == 'zh' ? '保存中…' : 'Saving…') : '💾 ${t.save}',
            color: kGreenBg, borderColor: kGreenBd, textColor: kGreen,
            onTap: _saving ? () {} : () => _save(),
          ),
          const SizedBox(width: 8),
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

          // ── Credit note details ───────────────────────────────────────────
          _SectionBox(
            title: lang == 'zh' ? '信用备注信息' : 'Credit Note Details',
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Row(children: [
                  Expanded(child: FieldInput(
                    label: t.cnNo, value: _cnNo,
                    onChanged: (v) => setState(() => _cnNo = v),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(
                    label: t.cnDate, value: _cnDate,
                    keyboard: TextInputType.datetime,
                    onChanged: (v) => setState(() => _cnDate = v),
                  )),
                ]),
                FieldInput(
                  label: t.creditReason, value: _reason,
                  placeholder: lang == 'zh' ? '如：退货 / 多收 / 折扣调整' : 'e.g. Return / Overcharge',
                  onChanged: (v) => setState(() => _reason = v),
                ),
                // ── One-click invoice picker ────────────────────────────────
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
                              : (lang == 'zh' ? '点击选择原发票（带出客户+明细）'
                                              : 'Tap to select original invoice'),
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

          // ── Customer ──────────────────────────────────────────────────────
          _SectionBox(
            title: t.billTo,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_customer.id == 0 || _customer.name.isEmpty)
                  DashedBtn(
                    label: '👤 ${lang == 'zh' ? '选择客户' : 'Select Customer'}',
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

          // ── Line items ────────────────────────────────────────────────────
          _SectionBox(
            title: t.items,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ..._items.asMap().entries.map((e) => _CnItemRow(
                  index:     e.key,
                  item:      e.value,
                  lang:      lang,
                  onChanged: (updated) => setState(() => _items[e.key] = updated),
                  onRemove:  _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
                )),
                const SizedBox(height: 8),
                DashedBtn(
                  label: '+ ${t.addLine}',
                  onTap: () => setState(() => _items.add(
                    {'desc': '', 'qty': '1', 'price': '', 'disc': '', 'sst': 'none', 'note': ''})),
                ),
                const SizedBox(height: 16),
                _TotalsRow(label: t.subTotal, value: _subtotal),
                if (_totalSST > 0) _TotalsRow(label: t.sstAmt, value: _totalSST),
                const Divider(color: kBorder, height: 20),
                _TotalsRow(label: t.totalCredit, value: _grand, bold: true, negative: true),
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

// ── Item row (description + qty + price + disc + SST) ────────────────────────────
class _CnItemRow extends StatelessWidget {
  final int index;
  final Map<String, String> item;
  final String lang;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback? onRemove;
  const _CnItemRow({required this.index, required this.item, required this.lang,
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
          Expanded(child: FieldInput(
            label: t.unitPrice, value: item['price'] ?? '',
            keyboard: TextInputType.number,
            onChanged: (v) => _up('price', v),
          )),
          const SizedBox(width: 8),
          Expanded(child: FieldInput(
            label: lang == 'zh' ? '折扣 (%)' : 'Disc (%)', value: item['disc'] ?? '',
            keyboard: TextInputType.number,
            onChanged: (v) => _up('disc', v),
          )),
        ]),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: item['sst'] ?? 'none',
          items: sstRates.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(lang == 'zh' ? e.value.zhLabel : e.value.enLabel,
                style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: (v) { if (v != null) _up('sst', v); },
          decoration: InputDecoration(
            labelText: lang == 'zh' ? 'SST / 税率' : 'SST / Tax',
            labelStyle: const TextStyle(fontSize: 12, color: kMuted),
            filled: true, fillColor: kSurface,
            isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kBorder)),
          ),
        ),
      ]),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  final String label;
  final double value;
  final bool   bold;
  final bool   negative;
  const _TotalsRow({required this.label, required this.value,
      this.bold = false, this.negative = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          color: bold ? kText : kMuted)),
      Text('${negative ? '-' : ''}${fmtMYR(value)}', style: TextStyle(
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
          color: negative ? kRed : kText)),
    ]),
  );
}

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
