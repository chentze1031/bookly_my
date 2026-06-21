import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'payroll_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/common.dart';
import '../services/myinvois_service.dart';
import 'delivery_order_screen.dart';
import 'credit_note_screen.dart';
import 'payroll_reports_screen.dart';
import 'leave_management_screen.dart';
import 'sub_screen.dart' show showSubSheet;

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE HISTORY
// ═══════════════════════════════════════════════════════════════════════════

class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});
  @override State<InvoiceHistoryScreen> createState() => _InvoiceHistoryState();
}

class _InvoiceHistoryState extends State<InvoiceHistoryScreen> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadInvoices();
    // Newest invoice on top: by invoice date desc, then invoice no desc.
    list.sort((a, b) {
      final d = (b['invDate'] ?? '').toString().compareTo((a['invDate'] ?? '').toString());
      return d != 0 ? d : (b['invNo'] ?? '').toString().compareTo((a['invNo'] ?? '').toString());
    });
    if (mounted) setState(() { _invoices = list; _loading = false; });
  }

  Future<void> _exportPdf(Map<String, dynamic> inv) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer'] ?? {}));
      final items = (inv['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      // MyInvois validation QR (#28): only when the invoice is validated.
      String? miUrl, miUuid;
      if (inv['miStatus'] == 'Valid' && inv['miUuid'] != null && inv['miLongId'] != null) {
        final creds = await MyInvoisService.loadCredentials();
        // Prefer the env stored at submission; fall back to the current setting
        // for invoices submitted before miEnv was tracked.
        final env = (inv['miEnv'] ?? creds?['env'] ?? 'sandbox') as String;
        miUuid = inv['miUuid'] as String;
        miUrl = MyInvoisService.validationUrl(env, miUuid, inv['miLongId'] as String);
      }
      final bytes = await generateInvoicePdf(
        co: app.settings, customer: customer, rows: items,
        invNo: inv['invNo'] ?? '', invDate: inv['invDate'] ?? '',
        dueDate:  (inv['dueDate']  ?? '').isNotEmpty ? inv['dueDate']  : null,
        notes:    (inv['notes']    ?? '').isNotEmpty ? inv['notes']    : null,
        terms:    (inv['terms']    ?? '').isNotEmpty ? inv['terms']    : null,
        bankName: (inv['bankName'] ?? '').isNotEmpty ? inv['bankName'] : null,
        bankAcct: (inv['bankAcct'] ?? '').isNotEmpty ? inv['bankAcct'] : null,
        // Company logo + authorised signature (were missing on history export).
        logoBase64: app.settings.logoBase64,
        sigBase64:  app.settings.sigBase64,
        myInvoisUrl: miUrl, myInvoisUuid: miUuid,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (inv['invNo'] ?? 'inv').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Invoice_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Invoice ${inv['invNo']}');
      // FIX #3: 分享成功后触发广告
      context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(String invNo) async {
    await context.read<AppState>().deleteInvoice(invNo);
    _load();
  }

  // Convert an invoice into a delivery order (Pro). Carries customer + items
  // (quantities only) and references the source invoice number.
  Future<void> _toDeliveryOrder(Map<String, dynamic> inv) async {
    if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
    final customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer'] ?? {}));
    final items = (inv['items'] as List? ?? [])
        .map((e) => Map<String, String>.from(e)).toList();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => DeliveryOrderSheet(
        initCustomer: customer,
        initItems:    items,
        refInvNo:     inv['invNo'] as String?,
      ),
    ));
  }

  // Convert an invoice into a credit note (Pro). Carries customer + items and
  // references the source invoice; the credit note reduces AR on save.
  Future<void> _toCreditNote(Map<String, dynamic> inv) async {
    if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
    final customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer'] ?? {}));
    final items = (inv['items'] as List? ?? [])
        .map((e) => Map<String, String>.from(e)).toList();
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreditNoteSheet(
        initCustomer: customer,
        initItems:    items,
        refInvNo:     inv['invNo'] as String?,
      ),
    ));
  }

  // Calculate invoice total from items
  static double _total(Map<String, dynamic> inv) {
    const sstMap = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};
    return (inv['items'] as List? ?? []).fold<double>(0, (s, r) {
      final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
      final price = double.tryParse(r['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      return s + net + net * (sstMap[r['sst'] ?? 'none'] ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Invoice History', '发票记录', 'Sejarah Invois')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _invoices.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('🧾', style: TextStyle(fontSize: 48)),
              SizedBox(height: 12),
              Text('No invoices saved yet', style: TextStyle(color: kMuted, fontSize: 15)),
            ]))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _invoices.length,
                itemBuilder: (_, i) {
                  final inv = _invoices[i];
                  return _InvoiceCard(
                    inv: inv,
                    total: _total(inv),
                    lang: lang,
                    onView: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => _InvoiceDetailScreen(inv: inv, onExport: () => _exportPdf(inv)))),
                    onExport: () => _exportPdf(inv),
                    onDelete: () => _confirmDelete(context, inv['invNo'] ?? '', () => _delete(inv['invNo'] ?? '')),
                    onToDo: () => _toDeliveryOrder(inv),
                    onToCn: () => _toCreditNote(inv),
                  );
                },
              ),
            ),
    );
  }

  void _confirmDelete(BuildContext ctx, String invNo, VoidCallback onConfirm) {
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Delete Invoice?'),
      content: Text('Delete $invNo? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); onConfirm(); },
            child: Text('Delete', style: TextStyle(color: kRed))),
      ],
    ));
  }
}

// ── Invoice list card ─────────────────────────────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  final double total;
  final String lang;
  final VoidCallback onView, onExport, onDelete, onToDo, onToCn;
  const _InvoiceCard({required this.inv, required this.total, required this.lang,
      required this.onView, required this.onExport, required this.onDelete,
      required this.onToDo, required this.onToCn});

  @override
  Widget build(BuildContext context) {
    final customer = inv['customer'] as Map? ?? {};
    final items    = (inv['items'] as List? ?? []);
    return GestureDetector(
      onTap: onView,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: kBlueBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: kBlueBd))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv['invNo'] ?? '—',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kBlue)),
                Text(inv['invDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
              ])),
              Text(fmtMYR(total),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                ]),
              const SizedBox(height: 4),
              Text('${items.length} item${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: kMuted)),
              if ((inv['dueDate'] ?? '').isNotEmpty)
                Text('Due: ${inv['dueDate']}', style: TextStyle(fontSize: 11, color: kRed)),
              const SizedBox(height: 10),
              // Row 1: View / PDF / delete
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kBlue, side: const BorderSide(color: kBlueBd),
                      backgroundColor: kBlueBg,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExport,
                    icon: const Text('📤', style: TextStyle(fontSize: 13)),
                    label: const Text('PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kText, side: BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: kRed, size: 20),
                ),
              ]),
              const SizedBox(height: 6),
              // Row 2: convert to Delivery Order / Credit Note
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToDo,
                    icon: const Icon(Icons.local_shipping_outlined, size: 15),
                    label: Text(L10n(lang).convertToDo),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kGreen, side: const BorderSide(color: kGreenBd),
                      backgroundColor: kGreenBg,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToCn,
                    icon: const Icon(Icons.assignment_return_outlined, size: 15),
                    label: Text(L10n(lang).convertToCn),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kRed, side: const BorderSide(color: kRedBd),
                      backgroundColor: kRedBg,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Invoice detail screen ─────────────────────────────────────────────────────
class _InvoiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> inv;
  final VoidCallback onExport;
  const _InvoiceDetailScreen({required this.inv, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final customer = inv['customer'] as Map? ?? {};
    final items    = (inv['items'] as List? ?? []);
    const sstMap   = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};

    double subtotal = 0, totalSST = 0;
    final rows = items.map((r) {
      final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
      final price = double.tryParse(r['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      final sst   = net * (sstMap[r['sst'] ?? 'none'] ?? 0);
      subtotal += net; totalSST += sst;
      return (r: r, net: net, sst: sst, total: net + sst);
    }).toList();
    final grand = subtotal + totalSST;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(inv['invNo'] ?? 'Invoice'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: onExport,
            icon: const Text('📤', style: TextStyle(fontSize: 16)),
            label: const Text('Export PDF'),
            style: TextButton.styleFrom(foregroundColor: kText),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Invoice info ────────────────────────────────────────────
          _DetailSection(title: 'Invoice Info', color: kBlueBg, borderColor: kBlueBd, children: [
            _DetailRow('Invoice No', inv['invNo'] ?? '—'),
            _DetailRow('Date', inv['invDate'] ?? '—'),
            if ((inv['dueDate'] ?? '').isNotEmpty)
              _DetailRow('Due Date', inv['dueDate'], valueColor: kRed),
          ]),
          const SizedBox(height: 12),

          // ── MyInvois e-Invoice (Phase 4 #28) ───────────────────────────────
          _MyInvoisTile(inv: inv),
          const SizedBox(height: 12),

          // ── Bill to ─────────────────────────────────────────────────
          if ((customer['name'] ?? '').isNotEmpty) ...[
            _DetailSection(title: 'Bill To', color: kBg, borderColor: kBorder, children: [
              _DetailRow('Name', customer['name'] ?? ''),
              if ((customer['regNo']    ?? '').isNotEmpty) _DetailRow('Reg No', customer['regNo']),
              if ((customer['sstRegNo'] ?? '').isNotEmpty) _DetailRow('SST No', customer['sstRegNo']),
              if ((customer['address']  ?? '').isNotEmpty) _DetailRow('Address', customer['address'], multiline: true),
              if ((customer['phone']    ?? '').isNotEmpty) _DetailRow('Phone', customer['phone']),
              if ((customer['email']    ?? '').isNotEmpty) _DetailRow('Email', customer['email']),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Items ───────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(color: kBg,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    border: Border(bottom: BorderSide(color: kBorder))),
                child: const Text('ITEMS',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
              ),
              ...rows.asMap().entries.map((e) {
                final idx = e.key;
                final row = e.value;
                final r   = row.r;
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                      border: idx > 0 ? Border(top: BorderSide(color: kBorder)) : null),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r['desc'] ?? '',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kText))),
                      Text(fmtMYR(row.total),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
                    ]),
                    if ((r['note'] ?? '').isNotEmpty)
                      Text(r['note'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
                    const SizedBox(height: 2),
                    Text(
                      'Qty ${r['qty'] ?? '1'} × ${fmtMYR(double.tryParse(r['price'] ?? '0') ?? 0)}'
                      '${(r['disc'] ?? '').isNotEmpty && r['disc'] != '0' ? ' − ${r['disc']}%' : ''}'
                      '${row.sst > 0 ? ' + SST ${fmtMYR(row.sst)}' : ''}',
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ]),
                );
              }),
              // Totals
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: kBorder, width: 1.5))),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Subtotal', style: TextStyle(fontSize: 13, color: kMuted)),
                    Text(fmtMYR(subtotal), style: TextStyle(fontSize: 13, color: kText)),
                  ]),
                  if (totalSST > 0) ...[
                    const SizedBox(height: 3),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('SST', style: TextStyle(fontSize: 13, color: kMuted)),
                      Text(fmtMYR(totalSST), style: TextStyle(fontSize: 13, color: kText)),
                    ]),
                  ],
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(fmtMYR(grand),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kText)),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Bank / Notes / Terms ─────────────────────────────────────
          if ((inv['bankName'] ?? '').isNotEmpty || (inv['bankAcct'] ?? '').isNotEmpty) ...[
            _DetailSection(title: 'Payment To', color: kGreenBg, borderColor: kGreenBd, children: [
              if ((inv['bankName'] ?? '').isNotEmpty) _DetailRow('Bank', inv['bankName']),
              if ((inv['bankAcct'] ?? '').isNotEmpty) _DetailRow('Account', inv['bankAcct']),
            ]),
            const SizedBox(height: 12),
          ],
          if ((inv['notes'] ?? '').isNotEmpty) ...[
            _DetailSection(title: 'Notes', color: kBg, borderColor: kBorder, children: [
              _DetailRow('', inv['notes'], multiline: true),
            ]),
            const SizedBox(height: 12),
          ],
          if ((inv['terms'] ?? '').isNotEmpty) ...[
            _DetailSection(title: 'Terms & Conditions', color: kBg, borderColor: kBorder, children: [
              _DetailRow('', inv['terms'], multiline: true),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Export button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onExport,
              icon: const Text('📤', style: TextStyle(fontSize: 18)),
              label: const Text('Export PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAYROLL HISTORY
// ═══════════════════════════════════════════════════════════════════════════

class PayrollHistoryScreen extends StatefulWidget {
  const PayrollHistoryScreen({super.key});
  @override State<PayrollHistoryScreen> createState() => _PayrollHistoryState();
}

class _PayrollHistoryState extends State<PayrollHistoryScreen> {
  List<Map<String, dynamic>> _payrolls = [];
  bool _loading = true;

  static const _months = ['January','February','March','April','May','June',
    'July','August','September','October','November','December'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadPayrolls();
    if (mounted) setState(() { _payrolls = list; _loading = false; });
  }

  Future<void> _delete(String key) async {
    await context.read<AppState>().deletePayroll(key);
    _load();
  }

  static _PayrollCalc _calc(Map<String, dynamic> p) {
    final earn  = (p['earnings']   as List? ?? []);
    final ded   = (p['deductions'] as List? ?? []);
    final gross = earn.fold<double>(0, (s,e) => s + (double.tryParse(e['amount']??'0')??0));
    final otDed = ded.fold<double>(0,  (s,d) => s + (double.tryParse(d['amount']??'0')??0));
    final useEPF   = p['useEPF']   == true;
    final useSOCSO = p['useSOCSO'] == true;
    final useEIS   = p['useEIS']   == true;
    final eeEPF = useEPF   ? epfEe(gross)  : 0.0;
    final erEPF = useEPF   ? epfEr(gross)  : 0.0;
    final eeSSO = useSOCSO ? socsoEe(gross) : 0.0;
    final erSSO = useSOCSO ? socsoEr(gross) : 0.0;
    final eeEIS = useEIS   ? eisEe(gross)  : 0.0;
    final erEIS = useEIS   ? eisEr(gross)  : 0.0;
    final totDed = otDed + eeEPF + eeSSO + eeEIS;
    return _PayrollCalc(
      gross: gross, otDed: otDed, eeEPF: eeEPF, erEPF: erEPF,
      eeSSO: eeSSO, erSSO: erSSO, eeEIS: eeEIS, erEIS: erEIS,
      totDed: totDed, netPay: gross - totDed, erCost: gross + erEPF + erSSO + erEIS,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Payroll History', '薪资记录', 'Sejarah Gaji')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(children: [
            _hrHub(context, lang),
            Expanded(child: _payrolls.isEmpty
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('💼', style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text('No payslips saved yet', style: TextStyle(color: kMuted, fontSize: 15)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _payrolls.length,
                    itemBuilder: (_, i) {
                      final p   = _payrolls[i];
                      final c   = _calc(p);
                      return _PayrollCard(
                        p: p, calc: c, months: _months,
                        onView: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => _PayrollDetailScreen(p: p, calc: c, months: _months))),
                        onEdit: () => _reopenPayslip(context, p),
                        onTogglePaid: () => _togglePaid(p),
                        onDelete: () => _confirmDelete(context, p, c, () => _delete(p['key'] ?? '')),
                      );
                    },
                  ),
                )),
          ]),
    );
  }

  // ── HR & compliance hub (Phase 3 #11-14, Pro) ───────────────────────────────
  Widget _hrHub(BuildContext context, String lang) {
    void open(Widget screen) {
      if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    }
    final items = [
      ('🧾', tr(lang, 'CP39 (PCB)', 'CP39 扣税', 'CP39 (PCB)'),  const Cp39ReportScreen()),
      ('🏦', 'EPF/SOCSO/EIS',                       const StatutoryReportScreen()),
      ('📑', tr(lang, 'Form EA', 'EA 表格', 'Borang EA'),        const EaFormScreen()),
      ('🏖️', tr(lang, 'Leave', '请假管理', 'Cuti'),             const LeaveManagementScreen()),
    ];
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: items.map((it) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: () => open(it.$3),
            child: Container(
              width: 88,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Text(it.$1, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 6),
                Text(it.$2, textAlign: TextAlign.center, maxLines: 2,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kText)),
              ]),
            ),
          ),
        )).toList()),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, Map p, _PayrollCalc c, VoidCallback onConfirm) {
    final month = (p['month'] as int? ?? 1).clamp(1, 12);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Delete Payslip?'),
      content: Text('Delete payslip for ${p['empName']} (${_months[month - 1]} ${p['year']})?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); onConfirm(); },
            child: Text('Delete', style: TextStyle(color: kRed))),
      ],
    ));
  }

  void _reopenPayslip(BuildContext context, Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullPayrollSheet(prefill: r),
    );
  }

  Future<void> _togglePaid(Map<String, dynamic> r) async {
    // Phase 4 #C: routes through AppState so the settlement journal
    // (Dr payables / Cr bank) is posted when paid, removed when unpaid.
    await context.read<AppState>().setPayrollPaid((r['key'] ?? '').toString(), !(r['paid'] == true));
    _load();
  }
}

class _PayrollCalc {
  final double gross, otDed, eeEPF, erEPF, eeSSO, erSSO, eeEIS, erEIS, totDed, netPay, erCost;
  const _PayrollCalc({required this.gross, required this.otDed,
    required this.eeEPF, required this.erEPF, required this.eeSSO, required this.erSSO,
    required this.eeEIS, required this.erEIS, required this.totDed, required this.netPay,
    required this.erCost});
}

// ── Payroll list card ─────────────────────────────────────────────────────────
class _PayrollCard extends StatelessWidget {
  final Map<String, dynamic> p;
  final _PayrollCalc calc;
  final List<String> months;
  final VoidCallback onView, onEdit, onTogglePaid, onDelete;
  const _PayrollCard({required this.p, required this.calc, required this.months,
      required this.onView, required this.onEdit,
      required this.onTogglePaid, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final month   = (p['month'] as int? ?? 1).clamp(1, 12);
    final year    = p['year']  as int? ?? 0;
    final name    = p['empName'] as String? ?? '—';
    final savedAt = (p['savedAt'] as String? ?? '').length >= 10
        ? (p['savedAt'] as String).substring(0, 10) : '';
    final paid    = p['paid'] == true;

    return GestureDetector(
      onTap: onView,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
                color: paid ? kGreenBg : const Color(0xFFF8F9FA),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: paid ? kGreenBd : kBorder))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${months[month - 1]} $year',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
                        color: paid ? kGreen : kText)),
                if (savedAt.isNotEmpty)
                  Text('Saved $savedAt', style: const TextStyle(fontSize: 11, color: kMuted)),
              ])),
              // Paid/Draft badge
              GestureDetector(
                onTap: onTogglePaid,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: paid ? kGreen : kBg,
                    border: Border.all(color: paid ? kGreen : kBorder),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    paid ? '✓ Paid' : 'Draft',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: paid ? Colors.white : kMuted)),
                ),
              ),
              const SizedBox(width: 10),
              Text(fmtMYR(calc.netPay),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(children: [
              Row(children: [
                Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: kDark, shape: BoxShape.circle),
                    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                  Text('Gross ${fmtMYR(calc.gross)} · Net ${fmtMYR(calc.netPay)}',
                      style: const TextStyle(fontSize: 11, color: kMuted)),
                ])),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                    label: const Text('View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kGreen, side: const BorderSide(color: kGreenBd),
                      backgroundColor: kGreenBg,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
                const SizedBox(width: 6),
                // Edit button
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kText, side: BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: kRed, size: 20),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Payroll detail screen ─────────────────────────────────────────────────────
class _PayrollDetailScreen extends StatefulWidget {
  final Map<String, dynamic> p;
  final _PayrollCalc calc;
  final List<String> months;
  const _PayrollDetailScreen({required this.p, required this.calc, required this.months});
  @override State<_PayrollDetailScreen> createState() => _PayrollDetailState();
}

class _PayrollDetailState extends State<_PayrollDetailScreen> {
  bool _exporting = false;

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final app  = context.read<AppState>();
      final p    = widget.p;
      final c    = widget.calc;
      final name = p['empName'] as String? ?? '';
      final month= (p['month'] as int? ?? 1).clamp(1, 12);
      final year = p['year']  as int? ?? 0;
      final coName = app.settings.companyName.isNotEmpty ? app.settings.companyName : 'Company';
      final coAddr = app.settings.coAddr;
      final earn = (p['earnings']   as List? ?? []);
      final ded  = (p['deductions'] as List? ?? []);

      // Load CJK font
      pw.Font? cjkFont;
      try {
        final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
        cjkFont = pw.Font.ttf(fd);
      } catch (_) {}

      final pdf = pw.Document(
        theme: cjkFont != null ? pw.ThemeData.withFont(base: cjkFont, bold: cjkFont) : pw.ThemeData(),
      );

      const darkC   = PdfColor.fromInt(0xFF1A1A1A);
      const greenC  = PdfColor.fromInt(0xFF16A34A);
      const redC    = PdfColor.fromInt(0xFFDC2626);
      const mutedC  = PdfColor.fromInt(0xFF6B7280);
      const borderC = PdfColor.fromInt(0xFFE5E5E0);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          final earnRows = earn.where((e) => (double.tryParse(e['amount']??'0')??0) > 0).toList();
          final dedRows  = ded.where((d)  => (double.tryParse(d['amount']??'0')??0) > 0).toList();

          pw.Widget row(String label, String value, {bool bold=false, PdfColor? vc}) =>
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5),
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: borderC, width: 0.5))),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(label, style: pw.TextStyle(fontSize: 10, color: bold ? darkC : mutedC,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
                pw.Text(value, style: pw.TextStyle(fontSize: 10, color: vc ?? darkC,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              ]),
            );

          return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(color: darkC, borderRadius: pw.BorderRadius.circular(12)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('PAYSLIP', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white, letterSpacing: 2)),
                  pw.SizedBox(height: 4),
                  pw.Text('${widget.months[month-1]} $year',
                      style: pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFF9CA3AF))),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text(coName, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                  if (coAddr.isNotEmpty)
                    pw.Text(coAddr, style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF9CA3AF))),
                ]),
              ]),
            ),
            pw.SizedBox(height: 16),

            // Employee
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFF8F8F6),
                  border: pw.Border.all(color: borderC), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Row(children: [
                pw.Container(width: 40, height: 40,
                  decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF2563EB), shape: pw.BoxShape.circle),
                  alignment: pw.Alignment.center,
                  child: pw.Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                ),
                pw.SizedBox(width: 12),
                pw.Text(name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: darkC)),
              ]),
            ),
            pw.SizedBox(height: 14),

            // Earnings & Deductions side by side
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF0FDF4), borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromInt(0xFFBBF7D0))),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('EARNINGS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                      color: greenC, letterSpacing: 1)),
                  pw.SizedBox(height: 8),
                  ...earnRows.map((e) => row(e['desc']??'', fmtMYR(double.tryParse(e['amount']??'0')??0))),
                  pw.SizedBox(height: 4),
                  row('GROSS PAY', fmtMYR(c.gross), bold: true, vc: greenC),
                ]),
              )),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFFFF5F5), borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromInt(0xFFFECACA))),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('DEDUCTIONS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold,
                      color: redC, letterSpacing: 1)),
                  pw.SizedBox(height: 8),
                  if (p['useEPF']   == true) row('EPF',   fmtMYR(c.eeEPF)),
                  if (p['useSOCSO'] == true) row('SOCSO', fmtMYR(c.eeSSO)),
                  if (p['useEIS']   == true) row('EIS',   fmtMYR(c.eeEIS)),
                  ...dedRows.map((d) => row(d['desc']??'', fmtMYR(double.tryParse(d['amount']??'0')??0))),
                  pw.SizedBox(height: 4),
                  row('TOTAL DED.', '(${fmtMYR(c.totDed)})', bold: true, vc: redC),
                ]),
              )),
            ]),
            pw.SizedBox(height: 14),

            // Net Pay
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: pw.BoxDecoration(color: darkC, borderRadius: pw.BorderRadius.circular(10)),
              child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('NET PAY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white, letterSpacing: 1)),
                pw.Text(fmtMYR(c.netPay), style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF4ADE80))),
              ]),
            ),
            pw.SizedBox(height: 6),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text('Total employer cost: ${fmtMYR(c.erCost)}',
                  style: pw.TextStyle(fontSize: 9, color: mutedC)),
            ]),
            pw.Spacer(),
            pw.Divider(color: borderC),
            pw.Text('Computer-generated payslip · ${DateTime.now().toIso8601String().substring(0,10)}',
                style: pw.TextStyle(fontSize: 8, color: mutedC)),
          ]);
        },
      ));

      final bytes = await pdf.save();
      final dir   = await getTemporaryDirectory();
      final safe  = name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file  = File('${dir.path}/Payslip_${safe}_${widget.months[month-1]}_$year.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Payslip — $name — ${widget.months[month-1]} $year');
      // FIX #3: 分享成功后触发广告
      context.read<SubState>().onShareAction();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p    = widget.p;
    final c    = widget.calc;
    final month = (p['month'] as int? ?? 1).clamp(1, 12);
    final year  = p['year']  as int? ?? 0;
    final name  = p['empName'] as String? ?? '—';
    final earn  = (p['earnings']   as List? ?? []);
    final ded   = (p['deductions'] as List? ?? []);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('$name — ${widget.months[month-1]} $year'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _exporting ? null : _exportPdf,
            icon: _exporting
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('📤', style: TextStyle(fontSize: 16)),
            label: const Text('PDF'),
            style: TextButton.styleFrom(foregroundColor: kText),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Net Pay banner ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(16)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('NET PAY', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
              Text(fmtMYR(c.netPay), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF4ADE80))),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Earnings ────────────────────────────────────────────────
          _DetailSection(title: 'Earnings', color: kGreenBg, borderColor: kGreenBd, children: [
            ...earn.where((e) => (double.tryParse(e['amount']??'0')??0) > 0).map((e) =>
              _DetailRow(e['desc']??'', fmtMYR(double.tryParse(e['amount']??'0')??0))),
            _DetailRow('Gross Pay', fmtMYR(c.gross), bold: true, valueColor: kGreen),
          ]),
          const SizedBox(height: 12),

          // ── Deductions ──────────────────────────────────────────────
          _DetailSection(title: 'Deductions', color: kRedBg, borderColor: kRedBd, children: [
            if (p['useEPF']   == true) _DetailRow('EPF (Employee)',   fmtMYR(c.eeEPF)),
            if (p['useSOCSO'] == true) _DetailRow('SOCSO (Employee)', fmtMYR(c.eeSSO)),
            if (p['useEIS']   == true) _DetailRow('EIS (Employee)',   fmtMYR(c.eeEIS)),
            ...ded.where((d) => (double.tryParse(d['amount']??'0')??0) > 0).map((d) =>
              _DetailRow(d['desc']??'', fmtMYR(double.tryParse(d['amount']??'0')??0))),
            _DetailRow('Total Deductions', fmtMYR(c.totDed), bold: true, valueColor: kRed),
          ]),
          const SizedBox(height: 12),

          // ── Statutory (employer contributions) ──────────────────────
          if (p['useEPF'] == true || p['useSOCSO'] == true || p['useEIS'] == true) ...[
            _DetailSection(title: 'Employer Contributions', color: kBlueBg, borderColor: kBlueBd, children: [
              if (p['useEPF']   == true) _DetailRow('EPF (Employer)',   fmtMYR(c.erEPF)),
              if (p['useSOCSO'] == true) _DetailRow('SOCSO (Employer)', fmtMYR(c.erSSO)),
              if (p['useEIS']   == true) _DetailRow('EIS (Employer)',   fmtMYR(c.erEIS)),
              _DetailRow('Total Employer Cost', fmtMYR(c.erCost), bold: true),
            ]),
            const SizedBox(height: 12),
          ],

          // ── Export button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _exporting ? null : _exportPdf,
              icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('📤', style: TextStyle(fontSize: 18)),
              label: Text(_exporting ? 'Exporting…' : 'Export PDF',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _DetailSection extends StatelessWidget {
  final String title;
  final Color color, borderColor;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.color,
      required this.borderColor, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(bottom: BorderSide(color: borderColor))),
        child: Text(title.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: kMuted, letterSpacing: 0.5)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(children: children),
      ),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? valueColor;
  final bool multiline;
  const _DetailRow(this.label, this.value, {this.bold = false, this.valueColor, this.multiline = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: label.isEmpty
      ? Text(value, style: TextStyle(fontSize: 13, color: valueColor ?? kMuted))
      : multiline
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 13, color: valueColor ?? kText,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          ])
        : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 13, color: kMuted)),
            Flexible(child: Text(value, textAlign: TextAlign.end,
                style: TextStyle(fontSize: 13, color: valueColor ?? kText,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
          ]),
  );
}


// ─── MyInvois submit tile (Phase 4 #28) ──────────────────────────────────────
class _MyInvoisTile extends StatefulWidget {
  final Map<String, dynamic> inv;
  const _MyInvoisTile({required this.inv});
  @override State<_MyInvoisTile> createState() => _MyInvoisTileState();
}

class _MyInvoisTileState extends State<_MyInvoisTile> {
  late String _status = (widget.inv['miStatus'] ?? 'none') as String;
  late String? _uuid    = widget.inv['miUuid'] as String?;
  late String? _longId  = widget.inv['miLongId'] as String?;
  late String? _subUid  = widget.inv['miSubmissionUid'] as String?;
  late String? _env     = widget.inv['miEnv'] as String?; // environment at submit time
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final app = context.read<AppState>();
    if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
    setState(() { _busy = true; _error = null; });
    final buyer = Customer.fromMap(Map<String, dynamic>.from(widget.inv['customer'] ?? {}));
    final r = await MyInvoisService.submitInvoice(
      invoice: widget.inv, supplier: app.settings, buyer: buyer);
    // Record the environment this invoice was submitted to (test vs live), so
    // the badge and validation QR always reflect the real submission target.
    final creds = await MyInvoisService.loadCredentials();
    final env = (creds?['env'] ?? 'sandbox').toString();
    await app.updateInvoiceMyInvois(widget.inv['invNo'] ?? '', {
      'miStatus': r.status, 'miSubmissionUid': r.submissionUid,
      'miUuid': r.uuid, 'miLongId': r.longId, 'miEnv': env,
    });
    if (mounted) setState(() {
      _busy = false; _status = r.status; _subUid = r.submissionUid;
      _uuid = r.uuid; _env = env; _error = r.error;
    });
  }

  Future<void> _refresh() async {
    if (_subUid == null) return;
    final app = context.read<AppState>();
    setState(() { _busy = true; _error = null; });
    final r = await MyInvoisService.checkStatus(_subUid!);
    await app.updateInvoiceMyInvois(widget.inv['invNo'] ?? '', {
      'miStatus': r.status, 'miUuid': r.uuid, 'miLongId': r.longId,
    });
    if (mounted) setState(() {
      _busy = false; _status = r.status; _uuid = r.uuid ?? _uuid;
      _longId = r.longId ?? _longId; _error = r.error;
    });
  }

  Future<void> _cancel() async {
    if (_uuid == null) return;
    final lang = context.read<AppState>().settings.lang;
    final reason = await _askReason(lang);
    if (reason == null || reason.trim().isEmpty) return;
    final app = context.read<AppState>();
    setState(() { _busy = true; _error = null; });
    final r = await MyInvoisService.cancelInvoice(_uuid!, reason.trim());
    if (r.ok) {
      await app.updateInvoiceMyInvois(widget.inv['invNo'] ?? '', {'miStatus': 'Cancelled'});
    }
    if (mounted) setState(() {
      _busy = false;
      if (r.ok) _status = 'Cancelled';
      _error = r.error;
    });
  }

  Future<String?> _askReason(String lang) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(lang, 'Cancel e-Invoice', '取消电子发票', 'Batal e-Invois'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true, maxLines: 2,
          decoration: InputDecoration(
            hintText: tr(lang, 'Reason for cancellation', '取消原因', 'Sebab pembatalan'),
            hintStyle: const TextStyle(color: kMuted),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(lang, 'Back', '返回', 'Kembali'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr(lang, 'Confirm', '确认', 'Sahkan'), style: TextStyle(color: kRed))),
        ],
      ),
    );
  }

  ({Color c, String label}) _badge(String lang) => switch (_status) {
    'Valid'      => (c: kGreen, label: tr(lang, 'Validated', '已验证', 'Disahkan')),
    'Invalid'    => (c: kRed,   label: tr(lang, 'Invalid', '无效', 'Tidak Sah')),
    'InProgress' => (c: kGold,  label: tr(lang, 'In progress', '处理中', 'Diproses')),
    'Cancelled'  => (c: kMuted, label: tr(lang, 'Cancelled', '已取消', 'Dibatalkan')),
    'Consolidated' => (c: kBlue, label: tr(lang, 'Consolidated', '已合并', 'Disatukan')),
    'error'      => (c: kRed,   label: tr(lang, 'Error', '错误', 'Ralat')),
    _            => (c: kMuted, label: tr(lang, 'Not submitted', '未提交', 'Belum hantar')),
  };

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final loggedIn = MyInvoisService.isLoggedIn;
    final buyerHasTin = ((widget.inv['customer'] as Map?)?['tin'] ?? '').toString().trim().isNotEmpty;
    final b = _badge(lang);
    return Container(
      decoration: BoxDecoration(
        color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🧾 ', style: TextStyle(fontSize: 15)),
          Text('MyInvois', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
          const Spacer(),
          if (_status != 'none') ...[ miEnvBadge(_env), const SizedBox(width: 6) ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: b.c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99), border: Border.all(color: b.c.withValues(alpha: 0.4))),
            child: Text(b.label, style: TextStyle(color: b.c, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        if (_uuid != null) ...[
          const SizedBox(height: 8),
          SelectableText('UUID: $_uuid', style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
        if (_status == 'Valid' && _longId != null) ...[
          const SizedBox(height: 4),
          SelectableText('Long ID: $_longId', style: const TextStyle(fontSize: 11, color: kMuted)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: TextStyle(fontSize: 11, color: kRed)),
        ],
        const SizedBox(height: 12),
        if (!loggedIn)
          Text(tr(lang, 'Sign in + configure MyInvois in Settings to submit.',
                  '请先登录并在设置里配置 MyInvois。', 'Log masuk + konfigur MyInvois di Tetapan.'),
              style: const TextStyle(fontSize: 12, color: kMuted))
        else if (_status == 'Cancelled')
          Text(tr(lang, 'This e-Invoice was cancelled.', '此电子发票已取消。', 'e-Invois ini telah dibatalkan.'),
              style: const TextStyle(fontSize: 12, color: kMuted))
        else if (_status == 'Consolidated')
          Text(tr(lang,
              'Included in a consolidated e-Invoice${widget.inv['miConsolidatedNo'] != null ? ' (${widget.inv['miConsolidatedNo']})' : ''}.',
              '已并入合并发票${widget.inv['miConsolidatedNo'] != null ? '（${widget.inv['miConsolidatedNo']}）' : ''}。',
              'Termasuk dalam e-Invois disatukan${widget.inv['miConsolidatedNo'] != null ? ' (${widget.inv['miConsolidatedNo']})' : ''}.'),
              style: TextStyle(fontSize: 12, color: kBlue))
        else if (_status == 'Valid')
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cancel_outlined, size: 18),
              style: OutlinedButton.styleFrom(foregroundColor: kRed, side: BorderSide(color: kRedBd)),
              label: Text(tr(lang, 'Cancel e-Invoice', '取消电子发票', 'Batal e-Invois')),
            ),
            const SizedBox(height: 4),
            Text(tr(lang,
                'Cancellation is only allowed within 72 hours of validation.',
                '仅可在验证后 72 小时内取消。',
                'Pembatalan hanya dibenarkan dalam 72 jam selepas pengesahan.'),
                style: const TextStyle(fontSize: 11, color: kMuted)),
          ])
        else if (_status == 'InProgress')
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: _busy ? null : _refresh,
              style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
              child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(tr(lang, 'Refresh status', '刷新状态', 'Semak status')),
            )),
          ])
        else if (!buyerHasTin)
          // B2C without a buyer TIN can't be a standalone e-Invoice — LHDN
          // requires these to go through the monthly consolidated submission.
          Text(tr(lang,
              'B2C invoice (no buyer TIN) → submit via Settings → MyInvois → Consolidated e-Invoice.',
              '该 B2C 发票（无买方 TIN）→ 请用「设置 → MyInvois → 合并发票」提交。',
              'Invois B2C (tiada TIN pembeli) → hantar di Tetapan → MyInvois → e-Invois Disatukan.'),
              style: const TextStyle(fontSize: 12, color: kMuted))
        else
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
              child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(tr(lang, 'Submit to MyInvois', '提交 MyInvois', 'Hantar ke MyInvois')),
            )),
          ]),
      ]),
    );
  }
}
