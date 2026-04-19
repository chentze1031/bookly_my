import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import '../utils.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/common.dart';

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
    if (mounted) setState(() { _invoices = list; _loading = false; });
  }

  Future<void> _exportPdf(Map<String, dynamic> inv) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer'] ?? {}));
      final items = (inv['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final bytes = await generateInvoicePdf(
        co: app.settings, customer: customer, rows: items,
        invNo: inv['invNo'] ?? '', invDate: inv['invDate'] ?? '',
        dueDate:  (inv['dueDate']  ?? '').isNotEmpty ? inv['dueDate']  : null,
        notes:    (inv['notes']    ?? '').isNotEmpty ? inv['notes']    : null,
        terms:    (inv['terms']    ?? '').isNotEmpty ? inv['terms']    : null,
        bankName: (inv['bankName'] ?? '').isNotEmpty ? inv['bankName'] : null,
        bankAcct: (inv['bankAcct'] ?? '').isNotEmpty ? inv['bankAcct'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (inv['invNo'] ?? 'inv').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Invoice_$safe.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Invoice ${inv['invNo']}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(String invNo) async {
    await context.read<AppState>().deleteInvoice(invNo);
    _load();
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
        title: Text(lang == 'zh' ? '发票记录' : 'Invoice History'),
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
                    onView: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => _InvoiceDetailScreen(inv: inv, onExport: () => _exportPdf(inv)))),
                    onExport: () => _exportPdf(inv),
                    onDelete: () => _confirmDelete(context, inv['invNo'] ?? '', () => _delete(inv['invNo'] ?? '')),
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
            child: const Text('Delete', style: TextStyle(color: kRed))),
      ],
    ));
  }
}

// ── Invoice list card ─────────────────────────────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  final double total;
  final VoidCallback onView, onExport, onDelete;
  const _InvoiceCard({required this.inv, required this.total,
      required this.onView, required this.onExport, required this.onDelete});

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
            decoration: const BoxDecoration(color: kBlueBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: kBlueBd))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inv['invNo'] ?? '—',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kBlue)),
                Text(inv['invDate'] ?? '', style: const TextStyle(fontSize: 11, color: kMuted)),
              ])),
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
              if ((inv['dueDate'] ?? '').isNotEmpty)
                Text('Due: ${inv['dueDate']}', style: const TextStyle(fontSize: 11, color: kRed)),
              const SizedBox(height: 10),
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
                      foregroundColor: kText, side: const BorderSide(color: kBorder),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
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
                decoration: const BoxDecoration(color: kBg,
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
                      border: idx > 0 ? const Border(top: BorderSide(color: kBorder)) : null),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r['desc'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kText))),
                      Text(fmtMYR(row.total),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
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
                decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kBorder, width: 1.5))),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Subtotal', style: TextStyle(fontSize: 13, color: kMuted)),
                    Text(fmtMYR(subtotal), style: const TextStyle(fontSize: 13, color: kText)),
                  ]),
                  if (totalSST > 0) ...[
                    const SizedBox(height: 3),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('SST', style: TextStyle(fontSize: 13, color: kMuted)),
                      Text(fmtMYR(totalSST), style: const TextStyle(fontSize: 13, color: kText)),
                    ]),
                  ],
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(fmtMYR(grand),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kText)),
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
        title: Text(lang == 'zh' ? '薪资记录' : 'Payroll History'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _payrolls.isEmpty
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
                    onDelete: () => _confirmDelete(context, p, c, () => _delete(p['key'] ?? '')),
                  );
                },
              ),
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
            child: const Text('Delete', style: TextStyle(color: kRed))),
      ],
    ));
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
  final VoidCallback onView, onDelete;
  const _PayrollCard({required this.p, required this.calc, required this.months,
      required this.onView, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final month   = (p['month'] as int? ?? 1).clamp(1, 12);
    final year    = p['year']  as int? ?? 0;
    final name    = p['empName'] as String? ?? '—';
    final savedAt = (p['savedAt'] as String? ?? '').length >= 10
        ? (p['savedAt'] as String).substring(0, 10) : '';

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
            decoration: const BoxDecoration(color: kGreenBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(bottom: BorderSide(color: kGreenBd))),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${months[month - 1]} $year',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kGreen)),
                if (savedAt.isNotEmpty)
                  Text('Saved $savedAt', style: const TextStyle(fontSize: 11, color: kMuted)),
              ])),
              Text(fmtMYR(calc.netPay),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(children: [
              Row(children: [
                Container(width: 36, height: 36,
                    decoration: const BoxDecoration(color: kDark, shape: BoxShape.circle),
                    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                  Text('Gross ${fmtMYR(calc.gross)} · Ded ${fmtMYR(calc.totDed)}',
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
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
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
