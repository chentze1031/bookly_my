import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../utils.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart';

// ─── Invoice History ──────────────────────────────────────────────────────────
class InvoiceHistoryScreen extends StatefulWidget {
  const InvoiceHistoryScreen({super.key});
  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryState();
}

class _InvoiceHistoryState extends State<InvoiceHistoryScreen> {
  List<Map<String, dynamic>> _invoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final list = await app.loadInvoices();
    if (mounted) setState(() { _invoices = list; _loading = false; });
  }

  Future<void> _share(Map<String, dynamic> inv) async {
    final app = context.read<AppState>();
    try {
      final customer = Customer.fromMap(Map<String, dynamic>.from(inv['customer'] ?? {}));
      final items = (inv['items'] as List).map((e) => Map<String, String>.from(e)).toList();
      final pdfBytes = await generateInvoicePdf(
        co:         app.settings,
        customer:   customer,
        rows:       items,
        invNo:      inv['invNo'] ?? '',
        invDate:    inv['invDate'] ?? '',
        dueDate:    inv['dueDate']?.isNotEmpty == true ? inv['dueDate'] : null,
        notes:      inv['notes']?.isNotEmpty == true ? inv['notes'] : null,
        terms:      inv['terms']?.isNotEmpty == true ? inv['terms'] : null,
        bankName:   inv['bankName']?.isNotEmpty == true ? inv['bankName'] : null,
        bankAcct:   inv['bankAcct']?.isNotEmpty == true ? inv['bankAcct'] : null,
      );
      final dir  = await getTemporaryDirectory();
      final safe = (inv['invNo'] ?? 'inv').replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Invoice_$safe.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Invoice ${inv['invNo']}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(String invNo) async {
    final app = context.read<AppState>();
    await app.deleteInvoice(invNo);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(lang == 'zh' ? '发票记录' : 'Invoice History'),
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('🧾', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 12),
                    Text('No invoices saved yet', style: TextStyle(color: kMuted, fontSize: 15)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _invoices.length,
                    itemBuilder: (_, i) => _InvoiceCard(
                      inv: _invoices[i],
                      lang: lang,
                      onShare: () => _share(_invoices[i]),
                      onDelete: () => _delete(_invoices[i]['invNo'] ?? ''),
                    ),
                  ),
                ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  final Map<String, dynamic> inv;
  final String lang;
  final VoidCallback onShare, onDelete;
  const _InvoiceCard({required this.inv, required this.lang, required this.onShare, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final customer = inv['customer'] as Map? ?? {};
    final items = (inv['items'] as List? ?? []);
    final total = items.fold<double>(0, (s, item) {
      final qty   = double.tryParse(item['qty']   ?? '1') ?? 1;
      final price = double.tryParse(item['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(item['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      const sstMap = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};
      final sst = net * (sstMap[item['sst'] ?? 'none'] ?? 0);
      return s + net + sst;
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: kBlueBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kBlueBd)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inv['invNo'] ?? '—',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kBlue)),
              Text(inv['invDate'] ?? '',
                  style: const TextStyle(fontSize: 11, color: kMuted)),
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
                    style: const TextStyle(fontSize: 13, color: kText, fontWeight: FontWeight.w600)),
              ]),
            const SizedBox(height: 4),
            Text('${items.length} item${items.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            if ((inv['dueDate'] ?? '').isNotEmpty)
              Text('Due: ${inv['dueDate']}',
                  style: const TextStyle(fontSize: 11, color: kRed)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Text('📤', style: TextStyle(fontSize: 14)),
                  label: const Text('Export PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kText,
                    side: const BorderSide(color: kBorder),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete Invoice?'),
                    content: Text('Delete ${inv['invNo']}? This cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () { Navigator.pop(context); onDelete(); },
                        child: const Text('Delete', style: TextStyle(color: kRed)),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ─── Payroll History ──────────────────────────────────────────────────────────
class PayrollHistoryScreen extends StatefulWidget {
  const PayrollHistoryScreen({super.key});
  @override
  State<PayrollHistoryScreen> createState() => _PayrollHistoryState();
}

class _PayrollHistoryState extends State<PayrollHistoryScreen> {
  List<Map<String, dynamic>> _payrolls = [];
  bool _loading = true;

  static const _months = ['January','February','March','April','May',
    'June','July','August','September','October','November','December'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final list = await app.loadPayrolls();
    if (mounted) setState(() { _payrolls = list; _loading = false; });
  }

  Future<void> _delete(String key) async {
    final app = context.read<AppState>();
    await app.deletePayroll(key);
    _load();
  }

  double _netPay(Map<String, dynamic> p) {
    final earnings    = (p['earnings']   as List? ?? []);
    final deductions  = (p['deductions'] as List? ?? []);
    final useEPF      = p['useEPF']   == true;
    final useSOCSO    = p['useSOCSO'] == true;
    final useEIS      = p['useEIS']   == true;
    final gross       = earnings.fold<double>(0, (s,e) => s + (double.tryParse(e['amount']??'0')??0));
    final otDed       = deductions.fold<double>(0, (s,d) => s + (double.tryParse(d['amount']??'0')??0));
    final eeEPF       = useEPF   ? epfEe(gross)  : 0.0;
    final eeSSO       = useSOCSO ? socsoEe(gross) : 0.0;
    final eeEIS       = useEIS   ? eisEe(gross)   : 0.0;
    return gross - otDed - eeEPF - eeSSO - eeEIS;
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(lang == 'zh' ? '薪资记录' : 'Payroll History'),
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _payrolls.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('💼', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 12),
                    Text('No payslips saved yet', style: TextStyle(color: kMuted, fontSize: 15)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _payrolls.length,
                    itemBuilder: (_, i) => _PayrollCard(
                      p: _payrolls[i],
                      net: _netPay(_payrolls[i]),
                      months: _months,
                      onDelete: () => _delete(_payrolls[i]['key'] ?? ''),
                    ),
                  ),
                ),
    );
  }
}

class _PayrollCard extends StatelessWidget {
  final Map<String, dynamic> p;
  final double net;
  final List<String> months;
  final VoidCallback onDelete;
  const _PayrollCard({required this.p, required this.net, required this.months, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final month = (p['month'] as int? ?? 1).clamp(1, 12);
    final year  = p['year']  as int? ?? 0;
    final name  = p['empName'] as String? ?? '—';
    final savedAt = (p['savedAt'] as String? ?? '').substring(0, 10.clamp(0, (p['savedAt'] as String? ?? '').length));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const BoxDecoration(
            color: kGreenBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kGreenBd)),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${months[month - 1]} $year',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kGreen)),
              Text('Saved $savedAt', style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            Text(fmtMYR(net),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: [
            Expanded(child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(color: kDark, shape: BoxShape.circle),
                child: Center(child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                )),
              ),
              const SizedBox(width: 10),
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
            ])),
            IconButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete Payslip?'),
                  content: Text('Delete payslip for $name (${months[month-1]} $year)?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () { Navigator.pop(context); onDelete(); },
                      child: const Text('Delete', style: TextStyle(color: kRed)),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.delete_outline, color: kRed, size: 20),
            ),
          ]),
        ),
      ]),
    );
  }
}
