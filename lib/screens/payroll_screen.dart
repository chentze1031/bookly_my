import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'invoice_screen.dart';


// ─── Employee Manager ─────────────────────────────────────────────────────────
class EmployeeManagerScreen extends StatefulWidget {
  final void Function(Employee)? onSelect;
  const EmployeeManagerScreen({super.key, this.onSelect});
  @override State<EmployeeManagerScreen> createState() => _EmpMgrState();
}

class _EmpMgrState extends State<EmployeeManagerScreen> {
  Employee? _editing;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t   = L10n(app.settings.lang);

    if (_editing != null) {
      return _EmpEditForm(
        emp: _editing!,
        t: t,
        onSave: (e) async {
          await app.saveEmployee(e);
          setState(() => _editing = null);
        },
        onCancel: () => setState(() => _editing = null),
      );
    }

    return Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(
        children: [
          SheetHandle(title: t.employees),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                DashedBtn(label: '+ ${t.newEmp}', onTap: () => setState(() => _editing = Employee(id: 0, name: ''))),
                const SizedBox(height: 10),
                if (app.employees.isEmpty)
                  const EmptyHint(icon: '👥', label: 'No employees yet'),
                ...app.employees.map((e) => _EmpCard(
                  emp: e,
                  onSelect: widget.onSelect != null ? () {
                    widget.onSelect!(e);
                    Navigator.pop(context);
                  } : null,
                  onEdit: () => setState(() => _editing = e),
                  onDelete: () => app.deleteEmployee(e.id),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmpCard extends StatelessWidget {
  final Employee emp;
  final VoidCallback? onSelect, onEdit;
  final VoidCallback onDelete;
  const _EmpCard({required this.emp, this.onSelect, this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    child: Row(children: [
      Container(
        width: 40, height: 40, decoration: const BoxDecoration(color: kDark, shape: BoxShape.circle),
        child: Center(child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
        if (emp.position.isNotEmpty)
          Text('${emp.position}${emp.department.isNotEmpty ? " · ${emp.department}" : ""}',
            style: const TextStyle(fontSize: 11, color: kMuted)),
        if (emp.basicSalary > 0)
          Text('RM ${emp.basicSalary.toStringAsFixed(2)}/mo',
            style: const TextStyle(fontSize: 11, color: kGreen)),
      ])),
      if (onSelect != null)
        SmBtn(label: 'Select', color: kDark, textColor: Colors.white, onTap: onSelect!),
      const SizedBox(width: 6),
      SmBtn(label: 'Edit', onTap: onEdit ?? () {}),
      const SizedBox(width: 6),
      GestureDetector(onTap: onDelete, child: const Icon(Icons.delete_outline, color: kRed, size: 22)),
    ]),
  );
}

class _EmpEditForm extends StatefulWidget {
  final Employee emp; final L10n t;
  final Future<void> Function(Employee) onSave;
  final VoidCallback onCancel;
  const _EmpEditForm({required this.emp, required this.t, required this.onSave, required this.onCancel});
  @override State<_EmpEditForm> createState() => _EmpEditFormState();
}

class _EmpEditFormState extends State<_EmpEditForm> {
  late Employee _e;
  bool _saving = false;

  @override
  void initState() { super.initState(); _e = widget.emp; }

  void _u(Employee e) => setState(() => _e = e);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.96),
      child: Column(
        children: [
          SheetHandle(
            title: _e.id == 0 ? t.newEmp : t.employees,
            trailing: TextButton(onPressed: widget.onCancel, child: const Text('← Back')),
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Personal
                _Subhead(label: 'Personal Info'),
                FieldInput(label: t.empName, value: _e.name, onChanged: (v) => _u(_e.copyWith(name: v))),
                Row(children: [
                  Expanded(child: FieldInput(label: t.empIC, value: _e.icNo, onChanged: (v) => _u(_e.copyWith(icNo: v)))),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(label: t.coPhone, value: _e.phone, keyboard: TextInputType.phone, onChanged: (v) => _u(_e.copyWith(phone: v)))),
                ]),
                FieldInput(label: t.coEmail, value: _e.email, keyboard: TextInputType.emailAddress, onChanged: (v) => _u(_e.copyWith(email: v))),

                // Employment
                _Subhead(label: 'Employment'),
                Row(children: [
                  Expanded(child: FieldInput(label: t.empPos,  value: _e.position,   onChanged: (v) => _u(_e.copyWith(position: v)))),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(label: t.empDept, value: _e.department, onChanged: (v) => _u(_e.copyWith(department: v)))),
                ]),
                FieldInput(label: t.empBasic, value: _e.basicSalary > 0 ? _e.basicSalary.toString() : '',
                  keyboard: TextInputType.number, onChanged: (v) => _u(_e.copyWith(basicSalary: double.tryParse(v) ?? 0))),

                // Statutory
                _Subhead(label: 'Statutory Numbers'),
                Row(children: [
                  Expanded(child: FieldInput(label: t.empEPF,   value: _e.epfNo,   onChanged: (v) => _u(_e.copyWith(epfNo: v)))),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(label: t.empSOCSO, value: _e.socsoNo, onChanged: (v) => _u(_e.copyWith(socsoNo: v)))),
                ]),

                // Bank
                _Subhead(label: 'Bank Details'),
                Row(children: [
                  Expanded(child: FieldInput(label: t.empBank, value: _e.bankName, onChanged: (v) => _u(_e.copyWith(bankName: v)))),
                  const SizedBox(width: 10),
                  Expanded(child: FieldInput(label: t.empAcct, value: _e.bankAcct, keyboard: TextInputType.number, onChanged: (v) => _u(_e.copyWith(bankAcct: v)))),
                ]),

                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _e.name.isEmpty || _saving ? null : () async {
                      setState(() => _saving = true);
                      await widget.onSave(_e);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)), elevation: 0),
                    child: Text(_saving ? 'Saving…' : t.save, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      ), // close Container
    );   // close Padding
  }
}

class _Subhead extends StatelessWidget {
  final String label;
  const _Subhead({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
  );
}

// ─── Payroll Sheet ────────────────────────────────────────────────────────────
class FullPayrollSheet extends StatefulWidget {
  const FullPayrollSheet({super.key});
  @override State<FullPayrollSheet> createState() => _PayrollSheetState();
}

class _PayrollSheetState extends State<FullPayrollSheet> {
  Employee? _emp;
  int _month = DateTime.now().month;
  int _year  = DateTime.now().year;

  List<Map<String, String>> _earn = [
    {'desc': 'Basic Salary', 'amount': ''},
    {'desc': 'Overtime',     'amount': ''},
    {'desc': 'Allowance',    'amount': ''},
  ];

  List<Map<String, String>> _ded = [
    {'desc': 'Absent Deduction', 'amount': ''},
    {'desc': 'Loan Repayment',   'amount': ''},
  ];

  bool _useEPF   = true;
  bool _useSOCSO = true;
  bool _useEIS   = true;
  bool _sharing  = false;
  bool _saving   = false;   // ← NEW

  static const _months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

  // ── Calculations ─────────────────────────────────────────────────────────
  double get _gross  => _earn.fold(0, (s,e) => s + (double.tryParse(e['amount']??'0')??0));
  double get _otDed  => _ded.fold(0, (s,d) => s + (double.tryParse(d['amount']??'0')??0));
  double get _eeEPF  => _useEPF   ? epfEe(_gross)   : 0;
  double get _erEPF  => _useEPF   ? epfEr(_gross)   : 0;
  double get _eeSSO  => _useSOCSO ? socsoEe(_gross)  : 0;
  double get _erSSO  => _useSOCSO ? socsoEr(_gross)  : 0;
  double get _eeEIS  => _useEIS   ? eisEe(_gross)    : 0;
  double get _erEIS  => _useEIS   ? eisEr(_gross)    : 0;
  double get _totDed => _otDed + _eeEPF + _eeSSO + _eeEIS;
  double get _netPay => _gross - _totDed;
  double get _erCost => _gross + _erEPF + _erSSO + _erEIS;

  // ── Save payroll record to DB ─────────────────────────────────────────────
  Future<void> _savePayroll() async {
    if (_saving || _emp == null) return;
    setState(() => _saving = true);
    try {
      final app = context.read<AppState>();
      await app.savePayroll(
        emp:      _emp!,
        month:    _month,
        year:     _year,
        earnings: _earn,
        deductions: _ded,
        useEPF:   _useEPF,
        useSOCSO: _useSOCSO,
        useEIS:   _useEIS,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Text('✅ ', style: TextStyle(fontSize: 16)),
              Text('Payslip saved — ${_months[_month - 1]} $_year'),
            ]),
            backgroundColor: kDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        // Auto-close sheet after save
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          final nav = Navigator.of(context);
          if (nav.canPop()) nav.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Generate PDF payslip bytes ────────────────────────────────────────────
  Future<Uint8List> _buildPayslipPdf(AppState app) async {
    // ── CJK font ─────────────────────────────────────────────────────────────
    pw.Font? cjkFont;
    try {
      final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      cjkFont  = pw.Font.ttf(fd);
    } catch (_) {}
    final pdf = pw.Document(
      theme: cjkFont != null
          ? pw.ThemeData.withFont(base: cjkFont, bold: cjkFont)
          : pw.ThemeData(),
    );

    // ── Data ──────────────────────────────────────────────────────────────────
    final emp        = _emp!;
    final periodStr  = '${_months[_month - 1]} $_year';
    final genDate    = DateTime.now().toIso8601String().substring(0, 10);
    final coName     = app.settings.companyName.isNotEmpty
        ? app.settings.companyName : 'Company';

    final earnRows = _earn
        .where((e) => (double.tryParse(e['amount'] ?? '0') ?? 0) > 0
            && (e['desc'] ?? '').isNotEmpty)
        .toList();
    final dedRows = _ded
        .where((d) => (double.tryParse(d['amount'] ?? '0') ?? 0) > 0
            && (d['desc'] ?? '').isNotEmpty)
        .toList();

    // ── Palette ───────────────────────────────────────────────────────────────
    const cDark   = PdfColor.fromInt(0xFF0F172A); // slate-900
    const cSlate  = PdfColor.fromInt(0xFF334155); // slate-700
    const cMuted  = PdfColor.fromInt(0xFF64748B); // slate-500
    const cRule   = PdfColor.fromInt(0xFFE2E8F0); // slate-200
    const cBg     = PdfColor.fromInt(0xFFF8FAFC); // slate-50
    const cAccent = PdfColor.fromInt(0xFF0F172A); // same as dark — mono accent
    const cWhite  = PdfColors.white;

    // ── Type helpers ──────────────────────────────────────────────────────────
    pw.TextStyle h1() => pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold,
        color: cWhite, letterSpacing: 1.0);
    pw.TextStyle h2() => pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
        color: cDark);
    pw.TextStyle label() => pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold,
        color: cMuted, letterSpacing: 0.8);
    pw.TextStyle body() => pw.TextStyle(fontSize: 9, color: cDark);
    pw.TextStyle bodyMuted() => pw.TextStyle(fontSize: 8.5, color: cMuted);
    pw.TextStyle mono() => pw.TextStyle(fontSize: 9, color: cDark);
    pw.TextStyle monoBold() => pw.TextStyle(fontSize: 9,
        fontWeight: pw.FontWeight.bold, color: cDark);
    pw.TextStyle tag() => pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold,
        color: cMuted, letterSpacing: 0.6);

    // ── Widget helpers ────────────────────────────────────────────────────────
    pw.Widget hRule({double thick = 0.5, PdfColor? color}) =>
        pw.Divider(thickness: thick, color: color ?? cRule, height: 0);

    pw.Widget gap(double h) => pw.SizedBox(height: h);

    // Section header pill
    pw.Widget sHead(String text) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(children: [
        pw.Container(width: 3, height: 12,
            decoration: pw.BoxDecoration(color: cDark,
                borderRadius: pw.BorderRadius.circular(2))),
        pw.SizedBox(width: 6),
        pw.Text(text, style: pw.TextStyle(fontSize: 8,
            fontWeight: pw.FontWeight.bold, color: cDark, letterSpacing: 0.6)),
      ]),
    );

    // A key-value info line
    pw.Widget infoLine(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(children: [
        pw.SizedBox(width: 110,
            child: pw.Text(k, style: bodyMuted())),
        pw.Expanded(child: pw.Text(v, style: body())),
      ]),
    );

    // Earnings / deduction row
    pw.Widget earningRow(String desc, String amount,
        {bool bold = false, bool isTotal = false}) {
      return pw.Container(
        decoration: isTotal
            ? null
            : pw.BoxDecoration(border: pw.Border(
                bottom: pw.BorderSide(color: cRule, width: 0.4))),
        padding: pw.EdgeInsets.symmetric(
            vertical: isTotal ? 6 : 4.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(desc,
                style: bold
                    ? pw.TextStyle(fontSize: 9,
                        fontWeight: pw.FontWeight.bold, color: cDark)
                    : body()),
            pw.Text(amount,
                style: bold
                    ? pw.TextStyle(fontSize: 9,
                        fontWeight: pw.FontWeight.bold, color: cDark)
                    : mono()),
          ],
        ),
      );
    }

    // Stat box (for the summary row)
    pw.Widget statBox(String label_, String amount,
        {bool highlight = false}) =>
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: highlight ? cDark : cBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: highlight
                  ? null
                  : pw.Border.all(color: cRule, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label_,
                    style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: highlight ? PdfColor.fromInt(0xFF94A3B8) : cMuted,
                        letterSpacing: 0.6)),
                gap(4),
                pw.Text(amount,
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: highlight ? cWhite : cDark)),
              ],
            ),
          ),
        );

    // ── Build page ────────────────────────────────────────────────────────────
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [

          // ╔══════════════════════════════════════════════════════════════════╗
          // ║  HEADER BAND                                                     ║
          // ╚══════════════════════════════════════════════════════════════════╝
          pw.Container(
            color: cDark,
            padding: const pw.EdgeInsets.fromLTRB(44, 30, 44, 26),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Left: title
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PAYSLIP', style: h1()),
                      gap(4),
                      pw.Text('Pay Period: $periodStr',
                          style: pw.TextStyle(fontSize: 10,
                              color: PdfColor.fromInt(0xFF94A3B8))),
                    ],
                  ),
                ),
                // Right: company
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(coName,
                        style: pw.TextStyle(fontSize: 12,
                            fontWeight: pw.FontWeight.bold, color: cWhite)),
                    if (app.settings.coReg.isNotEmpty)
                      pw.Text('Reg: ${app.settings.coReg}',
                          style: pw.TextStyle(fontSize: 8,
                              color: PdfColor.fromInt(0xFF94A3B8))),
                    if (app.settings.sstRegNo.isNotEmpty)
                      pw.Text('SST: ${app.settings.sstRegNo}',
                          style: pw.TextStyle(fontSize: 8,
                              color: PdfColor.fromInt(0xFF94A3B8))),
                    if (app.settings.coAddr.isNotEmpty)
                      pw.Text(app.settings.coAddr,
                          style: pw.TextStyle(fontSize: 8,
                              color: PdfColor.fromInt(0xFF94A3B8)),
                          textAlign: pw.TextAlign.right),
                  ],
                ),
              ],
            ),
          ),

          // ── thin accent stripe
          pw.Container(height: 4, color: PdfColor.fromInt(0xFF334155)),

          // ╔══════════════════════════════════════════════════════════════════╗
          // ║  BODY                                                            ║
          // ╚══════════════════════════════════════════════════════════════════╝
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(44, 26, 44, 0),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [

                  // ── Employee + Company info (2-col) ─────────────────────────
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Employee
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: cBg,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: cRule),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('EMPLOYEE', style: tag()),
                              gap(6),
                              pw.Text(emp.name, style: h2()),
                              if (emp.position.isNotEmpty) ...[
                                gap(2),
                                pw.Text(
                                  emp.department.isNotEmpty
                                      ? '${emp.position}  ·  ${emp.department}'
                                      : emp.position,
                                  style: bodyMuted()),
                              ],
                              gap(8),
                              if (emp.icNo.isNotEmpty)
                                infoLine('IC No.', emp.icNo),
                              if (emp.epfNo.isNotEmpty)
                                infoLine('EPF No.', emp.epfNo),
                              if (emp.socsoNo.isNotEmpty)
                                infoLine('SOCSO No.', emp.socsoNo),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      // Payment info
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: cBg,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: cRule),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('PAYMENT INFO', style: tag()),
                              gap(6),
                              infoLine('Pay Date',   genDate),
                              infoLine('Pay Period', periodStr),
                              if (emp.bankName.isNotEmpty)
                                infoLine('Bank', emp.bankName),
                              if (emp.bankAcct.isNotEmpty)
                                infoLine('Account No.', emp.bankAcct),
                              if (app.settings.coPhone.isNotEmpty)
                                infoLine('Company Tel', app.settings.coPhone),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  gap(20),

                  // ── Summary stats row ───────────────────────────────────────
                  pw.Row(children: [
                    statBox('GROSS EARNINGS', fmtMYR(_gross)),
                    pw.SizedBox(width: 8),
                    statBox('TOTAL DEDUCTIONS', '(${fmtMYR(_totDed)})'),
                    pw.SizedBox(width: 8),
                    statBox('NET PAY', fmtMYR(_netPay), highlight: true),
                  ]),

                  gap(20),

                  // ── Earnings & Deductions (2-col) ───────────────────────────
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Earnings column
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            sHead('EARNINGS'),
                            ...earnRows.map((e) {
                              final a = double.tryParse(e['amount'] ?? '0') ?? 0;
                              return earningRow(e['desc'] ?? '', fmtMYR(a));
                            }),
                            pw.Container(
                              margin: const pw.EdgeInsets.only(top: 4),
                              padding:
                                  const pw.EdgeInsets.fromLTRB(0, 6, 0, 0),
                              decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                      top: pw.BorderSide(
                                          color: cDark, width: 1.0))),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Gross Pay',
                                      style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: cDark)),
                                  pw.Text(fmtMYR(_gross),
                                      style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: cDark)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 24),
                      // Deductions column
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            sHead('DEDUCTIONS'),
                            if (_useEPF)
                              earningRow('EPF (Employee 11%)', fmtMYR(_eeEPF)),
                            if (_useSOCSO)
                              earningRow('SOCSO (Employee)', fmtMYR(_eeSSO)),
                            if (_useEIS)
                              earningRow('EIS (Employee)', fmtMYR(_eeEIS)),
                            ...dedRows.map((d) {
                              final a = double.tryParse(d['amount'] ?? '0') ?? 0;
                              return earningRow(d['desc'] ?? '', fmtMYR(a));
                            }),
                            pw.Container(
                              margin: const pw.EdgeInsets.only(top: 4),
                              padding:
                                  const pw.EdgeInsets.fromLTRB(0, 6, 0, 0),
                              decoration: pw.BoxDecoration(
                                  border: pw.Border(
                                      top: pw.BorderSide(
                                          color: cDark, width: 1.0))),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Total Deductions',
                                      style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: cDark)),
                                  pw.Text('(${fmtMYR(_totDed)})',
                                      style: pw.TextStyle(
                                          fontSize: 9,
                                          fontWeight: pw.FontWeight.bold,
                                          color: cDark)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  gap(20),

                  // ── Statutory breakdown table ────────────────────────────────
                  if (_useEPF || _useSOCSO || _useEIS) ...[
                    sHead('STATUTORY CONTRIBUTIONS (PERKESO / KWSP / SIP)'),
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: cRule),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(children: [
                        // Header
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFFF1F5F9),
                            borderRadius: const pw.BorderRadius.only(
                              topLeft: pw.Radius.circular(5),
                              topRight: pw.Radius.circular(5),
                            ),
                          ),
                          child: pw.Row(children: [
                            pw.Expanded(child: pw.Text('Contribution',
                                style: pw.TextStyle(fontSize: 7.5,
                                    fontWeight: pw.FontWeight.bold,
                                    color: cMuted))),
                            pw.SizedBox(width: 80,
                                child: pw.Text('Employee',
                                    style: pw.TextStyle(fontSize: 7.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: cMuted),
                                    textAlign: pw.TextAlign.right)),
                            pw.SizedBox(width: 80,
                                child: pw.Text('Employer',
                                    style: pw.TextStyle(fontSize: 7.5,
                                        fontWeight: pw.FontWeight.bold,
                                        color: cMuted),
                                    textAlign: pw.TextAlign.right)),
                          ]),
                        ),
                        hRule(),
                        // Rows
                        if (_useEPF)
                          _statRow('KWSP / EPF', fmtMYR(_eeEPF),
                              fmtMYR(_erEPF), cDark, cRule, body, mono),
                        if (_useSOCSO)
                          _statRow('PERKESO / SOCSO', fmtMYR(_eeSSO),
                              fmtMYR(_erSSO), cDark, cRule, body, mono),
                        if (_useEIS)
                          _statRow('SIP / EIS', fmtMYR(_eeEIS),
                              fmtMYR(_erEIS), cDark, cRule, body, mono),
                        // Employer total cost note
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(0xFFF8FAFC),
                            borderRadius: const pw.BorderRadius.only(
                              bottomLeft: pw.Radius.circular(5),
                              bottomRight: pw.Radius.circular(5),
                            ),
                            border: pw.Border(
                                top: pw.BorderSide(color: cRule)),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              pw.Text(
                                  'Total employer cost: ${fmtMYR(_erCost)}',
                                  style: pw.TextStyle(
                                      fontSize: 7.5,
                                      color: cMuted,
                                      fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                    gap(16),
                  ],

                  pw.Spacer(),

                  // ── Footer ──────────────────────────────────────────────────
                  pw.Container(
                    padding: const pw.EdgeInsets.fromLTRB(0, 12, 0, 20),
                    decoration: pw.BoxDecoration(
                        border: pw.Border(
                            top: pw.BorderSide(color: cRule, width: 0.8))),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        // Left: legal note
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'This payslip is issued in accordance with the Employment Act 1955 (Malaysia).',
                              style: pw.TextStyle(
                                  fontSize: 7, color: cMuted)),
                            pw.Text(
                              'Computer-generated — no signature required.  '
                              'Generated: $genDate',
                              style: pw.TextStyle(
                                  fontSize: 7, color: cMuted)),
                          ],
                        ),
                        // Right: net pay callout
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: pw.BoxDecoration(
                            color: cDark,
                            borderRadius: pw.BorderRadius.circular(6),
                          ),
                          child: pw.Row(children: [
                            pw.Text('NET PAY  ',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    color: PdfColor.fromInt(0xFF94A3B8),
                                    fontWeight: pw.FontWeight.bold,
                                    letterSpacing: 0.5)),
                            pw.Text(fmtMYR(_netPay),
                                style: pw.TextStyle(
                                    fontSize: 13,
                                    fontWeight: pw.FontWeight.bold,
                                    color: cWhite)),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));

    return pdf.save();
  }

  // ── Export as PDF and share ────────────────────────────────────────────────
  Future<void> _share() async {
    final app = context.read<AppState>();
    if (_emp == null) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _buildPayslipPdf(app);
      final dir   = await getTemporaryDirectory();
      final safeName = _emp!.name.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file  = File('${dir.path}/Payslip_${safeName}_${_months[_month-1]}_$_year.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Payslip — ${_emp!.name} — ${_months[_month-1]} $_year',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _updEarn(int i, String k, String v) =>
    setState(() { _earn = List.from(_earn); _earn[i][k] = v; });

  void _updDed(int i, String k, String v) =>
    setState(() { _ded = List.from(_ded); _ded[i][k] = v; });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t   = L10n(app.settings.lang);

    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      height: MediaQuery.of(context).size.height * 0.96 - keyboardH,
      child: Column(
        children: [
          // Top bar
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
            child: Row(children: [
              const Text('💼 ', style: TextStyle(fontSize: 20)),
              Text(t.payroll, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              const Spacer(),
              // ── Save button ──────────────────────────────────────
              SmBtn(
                label: _saving ? 'Saving…' : '💾 Save',
                color: kGreenBg,
                borderColor: kGreenBd,
                textColor: kGreen,
                onTap: (_saving || _emp == null) ? () {} : _savePayroll,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _sharing || _emp == null ? null : _share,
                icon: _sharing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('📤', style: TextStyle(fontSize: 16)),
                label: Text(_sharing ? 'Sharing…' : t.sharePrint),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _emp == null ? kBorder : kDark, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)), elevation: 0),
              ),
              const SizedBox(width: 8),
              GestureDetector(onTap: () => Navigator.pop(context),
                child: Container(width: 32, height: 32, decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 18, color: kMuted))),
            ]),
          ),

          // Form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [

                // ── Employee picker ───────────────────────────────────────
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.payEmp.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  if (_emp != null)
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Container(width: 40, height: 40, decoration: const BoxDecoration(color: kDark, shape: BoxShape.circle),
                          child: Center(child: Text(_emp!.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)))),
                        const SizedBox(width: 11),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_emp!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                          if (_emp!.position.isNotEmpty)
                            Text(_emp!.position, style: const TextStyle(fontSize: 11, color: kMuted)),
                        ])),
                        SmBtn(label: 'Change', onTap: () => _openEmpPicker(context, app, t)),
                      ]),
                    )
                  else
                    GestureDetector(
                      onTap: () => _openEmpPicker(context, app, t),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(border: Border.all(color: kBorder, width: 1.5, style: BorderStyle.solid), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Text('👤 ', style: TextStyle(fontSize: 20)),
                          Text(t.selEmp, style: const TextStyle(fontSize: 14, color: kMuted)),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 14),
                ]),

                // ── Pay period ────────────────────────────────────────────
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.payPeriod.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(11)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true, value: _month,
                          items: List.generate(12, (i) => DropdownMenuItem(value: i+1, child: Text(_months[i], style: const TextStyle(fontSize: 13)))),
                          onChanged: (v) => setState(() => _month = v!),
                        ),
                      ),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('YEAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(11)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true, value: _year,
                          items: [2024,2025,2026,2027].map((y) => DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (v) => setState(() => _year = v!),
                        ),
                      ),
                    ),
                  ])),
                ]),
                const SizedBox(height: 14),

                // ── Earnings ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: kGreenBg, border: Border.all(color: kGreenBd), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.earnings.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGreen, letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    ..._earn.asMap().entries.map((e) => _EarnRow(
                      item: e.value, i: e.key, type: 'earn',
                      onDescChanged: (v) => _updEarn(e.key, 'desc', v),
                      onAmtChanged:  (v) => _updEarn(e.key, 'amount', v),
                    )),
                    GestureDetector(
                      onTap: () => setState(() => _earn.add({'desc':'','amount':''})),
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(border: Border.all(color: kGreenBd, style: BorderStyle.solid), borderRadius: BorderRadius.circular(9)),
                        child: const Center(child: Text('+ Add Earning', style: TextStyle(color: kGreen, fontSize: 12))),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.only(top: 10),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: kGreenBd))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(t.grossPay, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
                        Text(fmtMYR(_gross), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kGreen)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // ── Statutory ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: kBlueBg, border: Border.all(color: kBlueBd), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.statutory.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBlue, letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    ToggleRow(
                      label: 'EPF — Ee: ${fmtMYR(_eeEPF)} · Er: ${fmtMYR(_erEPF)}',
                      value: _useEPF, activeColor: kBlue,
                      onChanged: (v) => setState(() => _useEPF = v),
                    ),
                    ToggleRow(
                      label: 'SOCSO — Ee: ${fmtMYR(_eeSSO)} · Er: ${fmtMYR(_erSSO)}',
                      value: _useSOCSO, activeColor: kPro,
                      onChanged: (v) => setState(() => _useSOCSO = v),
                    ),
                    ToggleRow(
                      label: 'EIS — Ee: ${fmtMYR(_eeEIS)} · Er: ${fmtMYR(_erEIS)}',
                      value: _useEIS, activeColor: const Color(0xFF0891B2),
                      onChanged: (v) => setState(() => _useEIS = v),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Ee = Employee deduction · Er = Employer cost',
                        style: TextStyle(fontSize: 10, color: kMuted)),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // ── Other deductions ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: kRedBg, border: Border.all(color: kRedBd), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.otherDed.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kRed, letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    ..._ded.asMap().entries.map((e) => _EarnRow(
                      item: e.value, i: e.key, type: 'ded',
                      onDescChanged: (v) => _updDed(e.key, 'desc', v),
                      onAmtChanged:  (v) => _updDed(e.key, 'amount', v),
                    )),
                    GestureDetector(
                      onTap: () => setState(() => _ded.add({'desc':'','amount':''})),
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 7),
                        decoration: BoxDecoration(border: Border.all(color: kRedBd, style: BorderStyle.solid), borderRadius: BorderRadius.circular(9)),
                        child: const Center(child: Text('+ Add Deduction', style: TextStyle(color: kRed, fontSize: 12))),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Summary ───────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _DarkRow(label: t.grossPay,   value: fmtMYR(_gross),   color: const Color(0xFF4ADE80)),
                    _DarkRow(label: t.totalDed,   value: '(${fmtMYR(_totDed)})', color: const Color(0xFFF87171)),
                    const Divider(color: Color(0xFF2A2820), height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(t.netPay, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(fmtMYR(_netPay), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF4ADE80))),
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${t.totalCost}: ${fmtMYR(_erCost)}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4B4840))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // ── Bottom action buttons ──────────────────────────────────
                if (_emp == null)
                  const Center(child: Text('Select an employee first', style: TextStyle(color: kMuted, fontSize: 13))),
                if (_emp != null)
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _savePayroll,
                        icon: _saving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('💾', style: TextStyle(fontSize: 16)),
                        label: Text(_saving ? 'Saving…' : t.save),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: kGreen,
                            side: const BorderSide(color: kGreenBd),
                            backgroundColor: kGreenBg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _sharing ? null : _share,
                        icon: _sharing
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('📤', style: TextStyle(fontSize: 20)),
                        label: Text(_sharing ? 'Sharing…' : t.sharePrint),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kDark,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
      ), // close Container
    );   // close Padding
  }

  void _openEmpPicker(BuildContext ctx, AppState app, L10n t) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => EmployeeManagerScreen(
        onSelect: (e) {
          setState(() {
            _emp = e;
            if (e.basicSalary > 0) {
              _earn = _earn.asMap().entries.map((entry) {
                if (entry.key == 0) return {'desc': 'Basic Salary', 'amount': e.basicSalary.toString()};
                return entry.value;
              }).toList();
            }
          });
        },
      ),
    );
  }
}


// ── Statutory table row helper ────────────────────────────────────────────────
pw.Widget _statRow(
  String label,
  String ee,
  String er,
  PdfColor textColor,
  PdfColor ruleColor,
  pw.TextStyle Function() bodyStyle,
  pw.TextStyle Function() monoStyle,
) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: ruleColor, width: 0.4))),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label, style: bodyStyle())),
        pw.SizedBox(width: 80,
            child: pw.Text(ee, style: monoStyle(), textAlign: pw.TextAlign.right)),
        pw.SizedBox(width: 80,
            child: pw.Text(er, style: monoStyle(), textAlign: pw.TextAlign.right)),
      ]),
    );


class _EarnRow extends StatelessWidget {
  final Map<String, String> item;
  final int i; final String type;
  final ValueChanged<String> onDescChanged, onAmtChanged;
  const _EarnRow({required this.item, required this.i, required this.type,
    required this.onDescChanged, required this.onAmtChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Expanded(flex: 2,
        child: TextField(
          controller: TextEditingController(text: item['desc'])..selection = TextSelection.collapsed(offset: (item['desc']??'').length),
          onChanged: onDescChanged,
          decoration: InputDecoration(
            hintText: type == 'earn' ? 'Earnings item' : 'Deduction item',
            filled: true, fillColor: kSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: kBorder)),
          ),
          style: const TextStyle(fontSize: 12, color: kText),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: TextEditingController(text: item['amount'])..selection = TextSelection.collapsed(offset: (item['amount']??'').length),
          onChanged: onAmtChanged,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0.00',
            filled: true, fillColor: kSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: kBorder)),
          ),
          style: const TextStyle(fontSize: 12, color: kText, fontFamily: 'monospace'),
        ),
      ),
    ]),
  );
}

class _DarkRow extends StatelessWidget {
  final String label, value; final Color color;
  const _DarkRow({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B6860))),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// needed by L10n
extension _PayrollL10n on L10n {
  String get payEmp      => isZh ? '员工' : 'Employee';
  String get totalDed    => isZh ? '总扣款' : 'Total Deductions';
  String get empIC       => isZh ? 'IC 号码' : 'IC No.';
  String get empPos      => isZh ? '职位' : 'Position';
  String get empDept     => isZh ? '部门' : 'Department';
  String get empBasic    => isZh ? '基本薪资 (MYR)' : 'Basic Salary (MYR)';
  String get empEPF      => 'EPF No.';
  String get empSOCSO    => 'SOCSO No.';
  String get empBank     => isZh ? '银行' : 'Bank';
  String get empAcct     => isZh ? '账号' : 'Account No.';
}
