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
import '../utils/quotation_pdf.dart';
import '../services/db_service.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart' show DashedBtn, SmBtn, CustomerManagerScreen, FullInvoiceSheet;

// ═══════════════════════════════════════════════════════════════════════════════
// QUOTATION HISTORY
// ═══════════════════════════════════════════════════════════════════════════════

class QuotationHistoryScreen extends StatefulWidget {
  const QuotationHistoryScreen({super.key});
  @override State<QuotationHistoryScreen> createState() => _QuotHistState();
}

class _QuotHistState extends State<QuotationHistoryScreen> {
  List<Map<String, dynamic>> _quots = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadQuotations();
    if (mounted) setState(() { _quots = list; _loading = false; });
  }

  static double _total(Map<String, dynamic> q) {
    const sstMap = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};
    return (q['items'] as List? ?? []).fold<double>(0, (s, r) {
      final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
      final price = double.tryParse(r['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      return s + net + net * (sstMap[r['sst'] ?? 'none'] ?? 0);
    });
  }

  Future<void> _exportPdf(Map<String, dynamic> q) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(q['customer'] ?? {}));
      final items = (q['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final bytes = await generateQuotationPdf(
        co:          app.settings,
        customer:    customer,
        rows:        items,
        quotNo:      q['quotNo'] ?? '',
        quotDate:    q['quotDate'] ?? '',
        validUntil:  (q['validUntil'] ?? '').isNotEmpty ? q['validUntil'] : null,
        logoBase64:  app.settings.logoBase64,
        notes:       (q['notes'] ?? '').isNotEmpty ? q['notes'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (q['quotNo'] ?? 'qt').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Quotation_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Quotation ${q['quotNo']}');
      context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _convertToInvoice(Map<String, dynamic> q) async {
    final app = context.read<AppState>();
    final customer = Customer.fromMap(Map<String, dynamic>.from(q['customer'] ?? {}));
    final items = (q['items'] as List).map((e) => Map<String, String>.from(e)).toList();

    // Mark as converted immediately
    await app.markQuotationStatus(q['quotNo'] ?? '', 'converted');
    await _load();

    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => FullInvoiceSheet(
        initCustomer:  customer,
        initItems:     items,
        initNotes:     q['notes'] as String?,
        fromQuotNo:    q['quotNo'] as String?,
      ),
    ));
  }

  Future<void> _delete(String quotNo) async {
    await context.read<AppState>().deleteQuotation(quotNo);
    _load();
  }

  void _confirmDelete(String quotNo) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Quotation?'),
      content: Text('Delete $quotNo? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () { Navigator.pop(context); _delete(quotNo); },
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
        title: Text(t.quotHistory),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kText),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QuotationSheet()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _quots.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('📋', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(lang == 'zh' ? '还没有报价单' : 'No quotations yet',
                  style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const QuotationSheet()));
                  _load();
                },
                icon: const Icon(Icons.add),
                label: Text(t.newQuotation),
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
                itemCount: _quots.length,
                itemBuilder: (_, i) {
                  final q = _quots[i];
                  return _QuotCard(
                    q: q,
                    total: _total(q),
                    lang: lang,
                    onExport:  () => _exportPdf(q),
                    onConvert: q['status'] == 'converted'
                        ? null
                        : () => _convertToInvoice(q),
                    onDelete:  () => _confirmDelete(q['quotNo'] ?? ''),
                    onEdit: () async {
                      await Navigator.push(context, MaterialPageRoute(
                        builder: (_) => QuotationSheet(existing: q),
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

// ── Quotation list card ────────────────────────────────────────────────────────
class _QuotCard extends StatelessWidget {
  final Map<String, dynamic> q;
  final double total;
  final String lang;
  final VoidCallback? onExport, onConvert, onDelete, onEdit;
  const _QuotCard({required this.q, required this.total, required this.lang,
      this.onExport, this.onConvert, this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t        = L10n(lang);
    final customer = q['customer'] as Map? ?? {};
    final items    = (q['items'] as List? ?? []);
    final status   = q['status'] as String? ?? 'draft';
    final statusColor = switch (status) {
      'accepted'  => kGreen,
      'rejected'  => kRed,
      'converted' => kBlue,
      'sent'      => const Color(0xFFD97706),
      _           => kMuted,
    };
    final statusLabel = switch (status) {
      'accepted'  => t.accepted,
      'rejected'  => t.rejected,
      'converted' => t.converted,
      'sent'      => t.sent,
      _           => t.draft,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: kBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: const Border(bottom: BorderSide(color: kBorder)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q['quotNo'] ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
              Text(q['quotDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
            ),
            const SizedBox(width: 10),
            Text(fmtMYR(total),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
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
            Text('${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            if ((q['validUntil'] ?? '').isNotEmpty)
              Text('${lang == 'zh' ? '有效至' : 'Valid'}: ${q['validUntil']}',
                  style: const TextStyle(fontSize: 11, color: kMuted)),
            const SizedBox(height: 10),
            // Action buttons
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
              if (onConvert != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onConvert,
                    icon: const Icon(Icons.receipt_long_outlined, size: 14),
                    label: Text(lang == 'zh' ? '转发票' : 'Invoice'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kGreen, side: const BorderSide(color: kGreenBd),
                      backgroundColor: kGreenBg,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: Text(lang == 'zh' ? '已转换' : 'Converted'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kMuted, side: const BorderSide(color: kBorder),
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
// QUOTATION SHEET (Create / Edit)
// ═══════════════════════════════════════════════════════════════════════════════

class QuotationSheet extends StatefulWidget {
  final Map<String, dynamic>? existing; // non-null → editing mode
  const QuotationSheet({super.key, this.existing});

  @override State<QuotationSheet> createState() => _QuotSheetState();
}

class _QuotSheetState extends State<QuotationSheet> {
  String _quotNo   = '';
  String _quotDate = nowISO();
  String _validUntil = '';
  String _notes    = '';
  bool   _saving   = false;
  bool   _sharing  = false;

  Customer _customer = Customer(id: 0, name: '');
  String? _logoB64;

  final List<Map<String, String>> _items = [
    {'desc': '', 'qty': '1', 'price': '', 'disc': '', 'sst': 'none', 'note': ''},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final q = widget.existing!;
      _quotNo     = q['quotNo'] ?? '';
      _quotDate   = q['quotDate'] ?? nowISO();
      _validUntil = q['validUntil'] ?? '';
      _notes      = q['notes'] ?? '';
      if (q['customer'] != null) {
        _customer = Customer.fromMap(Map<String, dynamic>.from(q['customer']));
      }
      if (q['items'] != null) {
        _items
          ..clear()
          ..addAll((q['items'] as List).map((e) => Map<String, String>.from(e)));
      }
    } else {
      // Auto-generate quotation number
      DbService.nextQuotNo().then((no) {
        if (mounted) setState(() => _quotNo = no);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<AppState>().settings;
      if (_logoB64 == null && settings.logoBase64 != null) {
        setState(() => _logoB64 = settings.logoBase64);
      }
    });
  }

  Map<String, double> _calcItem(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    final sub   = qty * price;
    final dAmt  = sub * (disc / 100);
    final net   = sub - dAmt;
    final sst   = net * (sstRates[r['sst'] ?? 'none']?.rate ?? 0);
    return {'sub': sub, 'disc': dAmt, 'net': net, 'sst': sst, 'total': net + sst};
  }

  double get _subtotal => _items.fold(0, (s, r) => s + (_calcItem(r)['net'] ?? 0));
  double get _totalSST => _items.fold(0, (s, r) => s + (_calcItem(r)['sst'] ?? 0));
  double get _grand    => _subtotal + _totalSST;

  Future<void> _save({String status = 'draft'}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().saveQuotation(
        quotNo:     _quotNo,
        quotDate:   _quotDate,
        validUntil: _validUntil,
        customer:   _customer,
        items:      List<Map<String, String>>.from(_items),
        notes:      _notes,
        status:     status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text('${_quotNo} ${status == 'sent' ? 'sent' : 'saved'}'),
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
      final pdfBytes = await generateQuotationPdf(
        co:         app.settings,
        customer:   _customer,
        rows:       List<Map<String, String>>.from(_items),
        quotNo:     _quotNo,
        quotDate:   _quotDate,
        validUntil: _validUntil.isNotEmpty ? _validUntil : null,
        logoBase64: _logoB64,
        notes:      _notes.isNotEmpty ? _notes : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = _quotNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Quotation_$safe.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Quotation $_quotNo');
      context.read<SubState>().onShareAction();
      if (mounted) await _save(status: 'sent');
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
          const Text('📋 ', style: TextStyle(fontSize: 20)),
          Text(t.quotation,
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

          // ── Quotation details ─────────────────────────────────────────────
          _SectionBox(
            title: lang == 'zh' ? '报价单信息' : 'Quotation Details',
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                FieldInput(
                  label: t.quotNo, value: _quotNo,
                  onChanged: (v) => setState(() => _quotNo = v),
                ),
                Row(children: [
                  Expanded(child: FieldInput(
                    label: t.quotDate, value: _quotDate,
                    onChanged: (v) => setState(() => _quotDate = v),
                    keyboard: TextInputType.datetime,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(
                    label: t.validUntil, value: _validUntil,
                    placeholder: 'YYYY-MM-DD',
                    onChanged: (v) => setState(() => _validUntil = v),
                    keyboard: TextInputType.datetime,
                  )),
                ]),
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

          // ── Line items ────────────────────────────────────────────────────
          _SectionBox(
            title: t.items,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ..._items.asMap().entries.map((e) => _ItemRow(
                  index:    e.key,
                  item:     e.value,
                  lang:     lang,
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
                // Totals
                _TotalsRow(label: t.subTotal,   value: _subtotal),
                if (_totalSST > 0) _TotalsRow(label: t.sstAmt, value: _totalSST),
                const Divider(color: kBorder, height: 20),
                _TotalsRow(label: t.grandTotal, value: _grand, bold: true),
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
                    ? '此报价单有效期内有效，详情请联系我们。'
                    : 'This quotation is valid for the period indicated.',
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

// ── Item row widget ────────────────────────────────────────────────────────────
class _ItemRow extends StatelessWidget {
  final int index;
  final Map<String, String> item;
  final String lang;
  final ValueChanged<Map<String, String>> onChanged;
  final VoidCallback? onRemove;
  const _ItemRow({required this.index, required this.item, required this.lang,
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

// ── Totals row ────────────────────────────────────────────────────────────────
class _TotalsRow extends StatelessWidget {
  final String label;
  final double value;
  final bool   bold;
  const _TotalsRow({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
          color: bold ? kText : kMuted)),
      Text(fmtMYR(value), style: TextStyle(
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.w900 : FontWeight.normal,
          color: kText)),
    ]),
  );
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

