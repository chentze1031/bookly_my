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
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      cjkFont = pw.Font.ttf(fontData);
    } catch (_) {}
    final pdf = pw.Document(
      theme: cjkFont != null
          ? pw.ThemeData.withFont(base: cjkFont, bold: cjkFont)
          : pw.ThemeData(),
    );

    final emp        = _emp!;
    final monthLabel = '${_months[_month - 1]} $_year';
    final coName     = app.settings.companyName.isNotEmpty ? app.settings.companyName : 'Company';
    final coAddr     = app.settings.coAddr;

    // ── Palette: black / grey only ────────────────────────────────────────────
    const _black  = PdfColors.black;
    const _grey   = PdfColor.fromInt(0xFF555555);
    const _light  = PdfColor.fromInt(0xFF888888);
    const _rule   = PdfColor.fromInt(0xFFBBBBBB);

    // ── Style helper ──────────────────────────────────────────────────────────
    pw.TextStyle ts(double sz, {PdfColor? c, bool bold = false}) => pw.TextStyle(
        fontSize: sz,
        color: c ?? _black,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

    pw.Widget div({double thick = 0.5}) =>
        pw.Divider(thickness: thick, color: _rule, height: 1);

    // ── Data helpers ──────────────────────────────────────────────────────────
    final earnRows = _earn.where((e) =>
        (double.tryParse(e['amount'] ?? '0') ?? 0) > 0 &&
        (e['desc'] ?? '').isNotEmpty).toList();
    final dedRows = _ded.where((d) =>
        (double.tryParse(d['amount'] ?? '0') ?? 0) > 0 &&
        (d['desc'] ?? '').isNotEmpty).toList();

    // One table row: label left, value right, hairline below
    pw.Widget row(String label, String value,
        {bool bold = false, bool last = false}) =>
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border(
                  bottom: last
                      ? pw.BorderSide.none
                      : pw.BorderSide(color: _rule, width: 0.5))),
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(label, style: ts(9, c: bold ? _black : _grey, bold: bold)),
                pw.Text(value, style: ts(9, bold: bold)),
              ]),
        );

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(52, 48, 52, 40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [

          // ══ HEADER: Company left | PAYSLIP + month right ══════════════════
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(coName, style: ts(12, bold: true)),
                    if (coAddr.isNotEmpty) pw.Text(coAddr, style: ts(8, c: _grey)),
                    if (app.settings.coPhone.isNotEmpty)
                      pw.Text(app.settings.coPhone, style: ts(8, c: _grey)),
                    if (app.settings.coEmail.isNotEmpty)
                      pw.Text(app.settings.coEmail, style: ts(8, c: _grey)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('PAYSLIP', style: ts(20, bold: true)),
                  pw.SizedBox(height: 4),
                  pw.Text(monthLabel, style: ts(10, c: _grey)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 18),
          div(thick: 1.0),
          pw.SizedBox(height: 12),

          // ══ EMPLOYEE ══════════════════════════════════════════════════════
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('EMPLOYEE', style: ts(7, c: _light, bold: true)),
                    pw.SizedBox(height: 4),
                    pw.Text(emp.name, style: ts(11, bold: true)),
                    if (emp.position.isNotEmpty)
                      pw.Text(emp.position, style: ts(9, c: _grey)),
                    if (emp.department.isNotEmpty)
                      pw.Text(emp.department, style: ts(9, c: _grey)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (emp.icNo.isNotEmpty)
                    pw.Text('IC: ${emp.icNo}', style: ts(8, c: _grey)),
                  if (emp.epfNo.isNotEmpty)
                    pw.Text('EPF: ${emp.epfNo}', style: ts(8, c: _grey)),
                  if (emp.socsoNo.isNotEmpty)
                    pw.Text('SOCSO: ${emp.socsoNo}', style: ts(8, c: _grey)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 14),
          div(),
          pw.SizedBox(height: 6),

          // ══ EARNINGS ══════════════════════════════════════════════════════
          pw.Text('EARNINGS', style: ts(7, c: _light, bold: true)),
          pw.SizedBox(height: 4),
          ...earnRows.map((e) {
            final amt = double.tryParse(e['amount'] ?? '0') ?? 0;
            return row(e['desc'] ?? '', fmtMYR(amt));
          }),
          row('Gross Pay', fmtMYR(_gross), bold: true, last: true),

          pw.SizedBox(height: 10),
          div(),
          pw.SizedBox(height: 6),

          // ══ DEDUCTIONS ════════════════════════════════════════════════════
          pw.Text('DEDUCTIONS', style: ts(7, c: _light, bold: true)),
          pw.SizedBox(height: 4),
          if (_useEPF)   row('EPF (Employee)',   fmtMYR(_eeEPF)),
          if (_useSOCSO) row('SOCSO (Employee)', fmtMYR(_eeSSO)),
          if (_useEIS)   row('EIS (Employee)',   fmtMYR(_eeEIS)),
          ...dedRows.map((d) {
            final amt = double.tryParse(d['amount'] ?? '0') ?? 0;
            return row(d['desc'] ?? '', fmtMYR(amt));
          }),
          row('Total Deductions', fmtMYR(_totDed), bold: true, last: true),

          // ── Statutory contributions (employee vs employer) ────────────────
          if (_useEPF || _useSOCSO || _useEIS) ...[
            pw.SizedBox(height: 10),
            div(),
            pw.SizedBox(height: 6),
            pw.Text('STATUTORY CONTRIBUTIONS', style: ts(7, c: _light, bold: true)),
            pw.SizedBox(height: 4),
            pw.Row(children: [
              pw.Expanded(child: pw.SizedBox()),
              pw.SizedBox(width: 70, child: pw.Text('Employee', style: ts(8, c: _grey, bold: true), textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: 70, child: pw.Text('Employer', style: ts(8, c: _grey, bold: true), textAlign: pw.TextAlign.right)),
            ]),
            pw.SizedBox(height: 3),
            if (_useEPF) pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFBBBBBB), width: 0.5))),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('EPF', style: ts(9))),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_eeEPF), style: ts(9), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_erEPF), style: ts(9), textAlign: pw.TextAlign.right)),
              ]),
            ),
            if (_useSOCSO) pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFBBBBBB), width: 0.5))),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('SOCSO', style: ts(9))),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_eeSSO), style: ts(9), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_erSSO), style: ts(9), textAlign: pw.TextAlign.right)),
              ]),
            ),
            if (_useEIS) pw.Container(
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFBBBBBB), width: 0.5))),
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('EIS', style: ts(9))),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_eeEIS), style: ts(9), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 70, child: pw.Text(fmtMYR(_erEIS), style: ts(9), textAlign: pw.TextAlign.right)),
              ]),
            ),
          ],

          pw.SizedBox(height: 14),
          div(thick: 1.0),
          pw.SizedBox(height: 8),

          // ══ NET PAY ═══════════════════════════════════════════════════════
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('NET PAY', style: ts(13, bold: true)),
              pw.Text(fmtMYR(_netPay), style: ts(16, bold: true)),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('Total employer cost: ${fmtMYR(_erCost)}',
                  style: ts(8, c: _light)),
            ],
          ),

          // ── Bank ─────────────────────────────────────────────────────────
          if (emp.bankName.isNotEmpty || emp.bankAcct.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            div(),
            pw.SizedBox(height: 6),
            pw.Row(children: [
              pw.Text('Bank Payment:  ', style: ts(8, c: _grey)),
              pw.Text('${emp.bankName}  ${emp.bankAcct}', style: ts(8, bold: true)),
            ]),
          ],

          pw.Spacer(),

          // ══ FOOTER ════════════════════════════════════════════════════════
          div(),
          pw.SizedBox(height: 6),
          pw.Text(
            'This is a computer-generated payslip.  '
            'Generated on ${DateTime.now().toIso8601String().substring(0, 10)}.',
            style: ts(7.5, c: _light),
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
