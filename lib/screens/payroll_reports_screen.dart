import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../utils/payroll_report_pdf.dart';
import 'payroll_screen.dart' show calcPcbMonthly;

// ═══════════════════════════════════════════════════════════════════════════════
// PAYROLL COMPLIANCE REPORTS (Phase 3 #11 CP39 · #12 EPF/SOCSO/EIS · #13 EA)
// Aggregates saved payrolls (loadPayrolls). All Pro.
// ═══════════════════════════════════════════════════════════════════════════════

const _months = ['January','February','March','April','May','June','July',
  'August','September','October','November','December'];

// Plain 2-decimal amount (no "RM") for table cells.
String _amt2(double v) => NumberFormat('#,##0.00').format(v);

// ── Per-payslip computed line ─────────────────────────────────────────────────
class _Line {
  final String empId, empName;
  final int month, year;
  final double gross, eeEPF, erEPF, eeSSO, erSSO, eeEIS, erEIS, pcb;
  _Line({required this.empId, required this.empName, required this.month,
    required this.year, required this.gross, required this.eeEPF, required this.erEPF,
    required this.eeSSO, required this.erSSO, required this.eeEIS, required this.erEIS,
    required this.pcb});

  double get epfTotal => eeEPF + erEPF;
  double get ssoTotal => eeSSO + erSSO;
  double get eisTotal => eeEIS + erEIS;
}

_Line _lineOf(Map<String, dynamic> p) {
  final earn  = (p['earnings'] as List? ?? []);
  final gross = earn.fold<double>(0, (s, e) => s + (double.tryParse(e['amount'] ?? '0') ?? 0));
  final useEPF   = p['useEPF']   == true;
  final useSOCSO = p['useSOCSO'] == true;
  final useEIS   = p['useEIS']   == true;
  return _Line(
    empId:   '${p['empId'] ?? ''}',
    empName: p['empName'] ?? '',
    month:   (p['month'] as int?) ?? 1,
    year:    (p['year']  as int?) ?? DateTime.now().year,
    gross:   gross,
    eeEPF: useEPF   ? epfEe(gross)  : 0, erEPF: useEPF   ? epfEr(gross)  : 0,
    eeSSO: useSOCSO ? socsoEe(gross): 0, erSSO: useSOCSO ? socsoEr(gross): 0,
    eeEIS: useEIS   ? eisEe(gross)  : 0, erEIS: useEIS   ? eisEr(gross)  : 0,
    pcb:   calcPcbMonthly(gross), // #11 decision: recompute PCB for all
  );
}

String _ic(AppState app, String empId) {
  final e = app.employees.where((x) => '${x.id}' == empId);
  return e.isEmpty ? '' : e.first.icNo;
}

// ── Shared month/year selector ─────────────────────────────────────────────────
class _PeriodBar extends StatelessWidget {
  final int month, year;            // month == 0 → year-only mode
  final List<int> years;
  final ValueChanged<int>? onMonth;
  final ValueChanged<int> onYear;
  const _PeriodBar({required this.month, required this.year, required this.years,
    this.onMonth, required this.onYear});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(children: [
        if (onMonth != null) ...[
          Expanded(child: _dropdown<int>(
            value: month,
            items: List.generate(12, (i) => i + 1),
            label: (m) => _months[m - 1],
            onChanged: (v) => onMonth!(v),
          )),
          const SizedBox(width: 10),
        ],
        Expanded(child: _dropdown<int>(
          value: years.contains(year) ? year : years.first,
          items: years,
          label: (y) => '$y',
          onChanged: onYear,
        )),
      ]),
    );
  }

  Widget _dropdown<T>({required T value, required List<T> items,
      required String Function(T) label, required ValueChanged<T> onChanged}) =>
    DropdownButtonFormField<T>(
      value: value,
      items: items.map((it) => DropdownMenuItem(value: it,
        child: Text(label(it), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      decoration: InputDecoration(
        filled: true, fillColor: kBg, isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      ),
    );
}

List<int> _availableYears(List<Map<String, dynamic>> payrolls) {
  final ys = payrolls.map((p) => (p['year'] as int?) ?? DateTime.now().year).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  if (ys.isEmpty) ys.add(DateTime.now().year);
  return ys;
}

Widget _emptyState(String msg) => Center(
  child: Padding(padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Text('📄', style: TextStyle(fontSize: 44)),
    const SizedBox(height: 12),
    Text(msg, style: const TextStyle(fontSize: 14, color: kMuted), textAlign: TextAlign.center),
  ])),
);

Future<void> _sharePdf(BuildContext context, List<int> bytes, String name) async {
  final dir  = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path, mimeType: 'application/pdf')], subject: name);
  if (context.mounted) context.read<SubState>().onShareAction();
}

// ═══════════════════════════════════════════════════════════════════════════════
// #11 — CP39 / PCB monthly report
// ═══════════════════════════════════════════════════════════════════════════════
class Cp39ReportScreen extends StatefulWidget {
  const Cp39ReportScreen({super.key});
  @override State<Cp39ReportScreen> createState() => _Cp39State();
}

class _Cp39State extends State<Cp39ReportScreen> {
  List<Map<String, dynamic>> _payrolls = [];
  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final list = await context.read<AppState>().loadPayrolls();
    if (mounted) setState(() { _payrolls = list; _loading = false; });
  }

  List<_Line> get _lines => _payrolls
      .where((p) => (p['month'] as int?) == _month && (p['year'] as int?) == _year)
      .map(_lineOf).where((l) => l.pcb > 0).toList();

  Future<void> _export(List<_Line> lines, double total) async {
    final app = context.read<AppState>();
    final bytes = await generateTableReportPdf(
      co: app.settings,
      title: 'CP39 — Monthly Tax Deduction (PCB/MTD)',
      subtitle: '${_months[_month - 1]} $_year',
      headers: ['No', 'Employee', 'IC No.', 'PCB (RM)'],
      flex: [1, 5, 4, 3],
      rightCols: [false, false, false, true],
      rows: lines.asMap().entries.map((e) => [
        '${e.key + 1}', e.value.empName, _ic(app, e.value.empId), _amt2(e.value.pcb),
      ]).toList(),
      totals: ['', 'TOTAL', '', _amt2(total)],
      note: 'PCB computed via Bookly MY estimator (annualised, RM9,000 relief). '
            'Verify against official LHDN PCB calculator before submission.',
    );
    if (mounted) await _sharePdf(context, bytes, 'CP39_${_year}_${_month.toString().padLeft(2,'0')}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final app  = context.read<AppState>();
    final lines = _lines;
    final total = lines.fold<double>(0, (s, l) => s + l.pcb);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(lang == 'zh' ? '🧾 CP39 月度扣税' : '🧾 CP39 (PCB)'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          if (lines.isNotEmpty)
            IconButton(icon: const Text('📤', style: TextStyle(fontSize: 18)),
              onPressed: () => _export(lines, total)),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        _PeriodBar(month: _month, year: _year, years: _availableYears(_payrolls),
          onMonth: (m) => setState(() => _month = m), onYear: (y) => setState(() => _year = y)),
        Expanded(child: lines.isEmpty
          ? _emptyState(lang == 'zh' ? '本月无应扣税的工资记录' : 'No taxable payroll this month')
          : ListView(padding: const EdgeInsets.all(16), children: [
              _TotalCard(label: lang == 'zh' ? '本月 PCB 总额' : 'Total PCB', value: total, color: const Color(0xFFF59E0B)),
              const SizedBox(height: 12),
              ...lines.map((l) => _ReportRow(
                title: l.empName,
                subtitle: '${lang == 'zh' ? 'IC' : 'IC'}: ${_ic(app, l.empId).isNotEmpty ? _ic(app, l.empId) : '—'} · ${lang == 'zh' ? '月薪' : 'Gross'} ${fmtMYR(l.gross)}',
                amount: l.pcb,
              )),
            ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// #12 — EPF / SOCSO / EIS contributions report
// ═══════════════════════════════════════════════════════════════════════════════
class StatutoryReportScreen extends StatefulWidget {
  const StatutoryReportScreen({super.key});
  @override State<StatutoryReportScreen> createState() => _StatutoryState();
}

class _StatutoryState extends State<StatutoryReportScreen> {
  List<Map<String, dynamic>> _payrolls = [];
  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final list = await context.read<AppState>().loadPayrolls();
    if (mounted) setState(() { _payrolls = list; _loading = false; });
  }

  List<_Line> get _lines => _payrolls
      .where((p) => (p['month'] as int?) == _month && (p['year'] as int?) == _year)
      .map(_lineOf).toList();

  Future<void> _export(List<_Line> lines) async {
    final app = context.read<AppState>();
    double tE = 0, tS = 0, tI = 0;
    for (final l in lines) { tE += l.epfTotal; tS += l.ssoTotal; tI += l.eisTotal; }
    final bytes = await generateTableReportPdf(
      co: app.settings,
      title: 'EPF / SOCSO / EIS Contributions',
      subtitle: '${_months[_month - 1]} $_year',
      headers: ['Employee', 'EPF (ee+er)', 'SOCSO', 'EIS', 'Total'],
      flex: [5, 3, 3, 3, 3],
      rightCols: [false, true, true, true, true],
      rows: lines.map((l) => [
        l.empName, _amt2(l.epfTotal), _amt2(l.ssoTotal), _amt2(l.eisTotal),
        _amt2(l.epfTotal + l.ssoTotal + l.eisTotal),
      ]).toList(),
      totals: ['TOTAL', _amt2(tE), _amt2(tS), _amt2(tI), _amt2(tE + tS + tI)],
      note: 'Each amount is employee + employer share combined. '
            'EPF: KWSP Form A · SOCSO/EIS: PERKESO Lampiran.',
    );
    if (mounted) await _sharePdf(context, bytes, 'EPF_SOCSO_EIS_${_year}_${_month.toString().padLeft(2,'0')}.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final lines = _lines;
    double tE = 0, tS = 0, tI = 0;
    for (final l in lines) { tE += l.epfTotal; tS += l.ssoTotal; tI += l.eisTotal; }
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(lang == 'zh' ? '🏦 EPF/SOCSO/EIS' : '🏦 EPF/SOCSO/EIS'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          if (lines.isNotEmpty)
            IconButton(icon: const Text('📤', style: TextStyle(fontSize: 18)), onPressed: () => _export(lines)),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        _PeriodBar(month: _month, year: _year, years: _availableYears(_payrolls),
          onMonth: (m) => setState(() => _month = m), onYear: (y) => setState(() => _year = y)),
        Expanded(child: lines.isEmpty
          ? _emptyState(lang == 'zh' ? '本月无工资记录' : 'No payroll this month')
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: _MiniTotal(label: 'EPF', value: tE)),
                const SizedBox(width: 8),
                Expanded(child: _MiniTotal(label: 'SOCSO', value: tS)),
                const SizedBox(width: 8),
                Expanded(child: _MiniTotal(label: 'EIS', value: tI)),
              ]),
              const SizedBox(height: 12),
              ...lines.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.empName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                  const SizedBox(height: 8),
                  _kv('EPF', l.eeEPF, l.erEPF, lang),
                  _kv('SOCSO', l.eeSSO, l.erSSO, lang),
                  _kv('EIS', l.eeEIS, l.erEIS, lang),
                ]),
              )),
            ])),
      ]),
    );
  }

  Widget _kv(String fund, double ee, double er, String lang) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      SizedBox(width: 56, child: Text(fund, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kMuted))),
      Expanded(child: Text('${lang == 'zh' ? '员工' : 'EE'} ${fmtMYR(ee)}', style: const TextStyle(fontSize: 12, color: kText))),
      Expanded(child: Text('${lang == 'zh' ? '雇主' : 'ER'} ${fmtMYR(er)}', style: const TextStyle(fontSize: 12, color: kText))),
      Text(fmtMYR(ee + er), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// #13 — EA form (annual income summary per employee)
// ═══════════════════════════════════════════════════════════════════════════════
class EaFormScreen extends StatefulWidget {
  const EaFormScreen({super.key});
  @override State<EaFormScreen> createState() => _EaState();
}

class _EaState extends State<EaFormScreen> {
  List<Map<String, dynamic>> _payrolls = [];
  int _year = DateTime.now().year;
  String? _empId;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final list = await context.read<AppState>().loadPayrolls();
    if (mounted) setState(() { _payrolls = list; _loading = false; });
  }

  // Employees that have payroll in the selected year
  List<MapEntry<String, String>> get _emps {
    final map = <String, String>{};
    for (final p in _payrolls.where((p) => (p['year'] as int?) == _year)) {
      map['${p['empId']}'] = p['empName'] ?? '';
    }
    return map.entries.toList();
  }

  List<_Line> _empLines(String empId) => _payrolls
      .where((p) => (p['year'] as int?) == _year && '${p['empId']}' == empId)
      .map(_lineOf).toList();

  Future<void> _export(String empId, String empName, List<_Line> lines) async {
    final app = context.read<AppState>();
    final gross = lines.fold<double>(0, (s, l) => s + l.gross);
    final epf   = lines.fold<double>(0, (s, l) => s + l.eeEPF);
    final pcb   = lines.fold<double>(0, (s, l) => s + l.pcb);
    final socso = lines.fold<double>(0, (s, l) => s + l.eeSSO);
    final bytes = await generateTableReportPdf(
      co: app.settings,
      title: 'Form EA — Annual Remuneration $_year',
      subtitle: '$empName${_ic(app, empId).isNotEmpty ? '  ·  IC ${_ic(app, empId)}' : ''}',
      headers: ['Item', 'Amount (RM)'],
      flex: [6, 3],
      rightCols: [false, true],
      rows: [
        ['Gross remuneration (B)', _amt2(gross)],
        ['EPF — employee (G)', _amt2(epf)],
        ['SOCSO — employee', _amt2(socso)],
        ['PCB / MTD deducted (F)', _amt2(pcb)],
        ['Months paid', '${lines.length}'],
      ],
      totals: ['Net of EPF & PCB', _amt2(gross - epf - pcb)],
      note: 'Summary for Form EA / CP8A. Figures are aggregated from saved payslips; '
            'confirm benefits-in-kind and reliefs separately.',
    );
    if (mounted) await _sharePdf(context, bytes, 'EA_${empName.replaceAll(RegExp(r"[^A-Za-z0-9]"), "_")}_$_year.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final app  = context.read<AppState>();
    final emps = _emps;
    if (_empId != null && !emps.any((e) => e.key == _empId)) _empId = null;
    final lines = _empId != null ? _empLines(_empId!) : <_Line>[];
    final gross = lines.fold<double>(0, (s, l) => s + l.gross);
    final epf   = lines.fold<double>(0, (s, l) => s + l.eeEPF);
    final pcb   = lines.fold<double>(0, (s, l) => s + l.pcb);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(lang == 'zh' ? '📑 EA 表格' : '📑 Form EA'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          if (lines.isNotEmpty)
            IconButton(icon: const Text('📤', style: TextStyle(fontSize: 18)),
              onPressed: () => _export(_empId!, emps.firstWhere((e) => e.key == _empId).value, lines)),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : Column(children: [
        Container(color: kSurface, padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            value: _availableYears(_payrolls).contains(_year) ? _year : _availableYears(_payrolls).first,
            items: _availableYears(_payrolls).map((y) => DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
            onChanged: (v) => setState(() { _year = v ?? _year; }),
            decoration: _dec(),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            value: _empId,
            hint: Text(lang == 'zh' ? '选择员工' : 'Select employee', style: const TextStyle(fontSize: 13)),
            items: emps.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _empId = v),
            decoration: _dec(),
          )),
        ])),
        Expanded(child: _empId == null
          ? _emptyState(lang == 'zh' ? '请选择员工查看 EA 汇总' : 'Select an employee to view EA summary')
          : lines.isEmpty
            ? _emptyState(lang == 'zh' ? '该员工本年无工资记录' : 'No payroll for this employee this year')
            : ListView(padding: const EdgeInsets.all(16), children: [
                _TotalCard(label: lang == 'zh' ? '$_year 年度毛收入' : 'Annual Gross $_year', value: gross, color: kBlue),
                const SizedBox(height: 12),
                _eaRow(lang == 'zh' ? '雇员 EPF (G)' : 'Employee EPF (G)', epf),
                _eaRow(lang == 'zh' ? 'PCB/MTD 已扣 (F)' : 'PCB/MTD deducted (F)', pcb),
                _eaRow(lang == 'zh' ? '发薪月数' : 'Months paid', lines.length.toDouble(), isCount: true),
                const Divider(color: kBorder, height: 24),
                _eaRow(lang == 'zh' ? '扣 EPF 及 PCB 后' : 'Net of EPF & PCB', gross - epf - pcb, bold: true),
              ])),
      ]),
    );
  }

  InputDecoration _dec() => InputDecoration(
    filled: true, fillColor: kBg, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
  );

  Widget _eaRow(String label, double v, {bool bold = false, bool isCount = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.normal, color: bold ? kText : kMuted)),
      Text(isCount ? v.toStringAsFixed(0) : fmtMYR(v), style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: kText)),
    ]),
  );
}

// ── Shared small widgets ──────────────────────────────────────────────────────
class _TotalCard extends StatelessWidget {
  final String label; final double value; final Color color;
  const _TotalCard({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      Text(fmtMYR(value), style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
    ]),
  );
}

class _MiniTotal extends StatelessWidget {
  final String label; final double value;
  const _MiniTotal({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(fmtMYR(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kText)),
    ]),
  );
}

class _ReportRow extends StatelessWidget {
  final String title, subtitle; final double amount;
  const _ReportRow({required this.title, required this.subtitle, required this.amount});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: kMuted)),
      ])),
      Text(fmtMYR(amount), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kText)),
    ]),
  );
}
