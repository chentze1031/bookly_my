import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
    return Container(
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
    );
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
    final pdf = pw.Document();
    final emp = _emp!;
    final monthLabel = '${_months[_month - 1]} $_year';
    final coName = app.settings.companyName.isNotEmpty ? app.settings.companyName : 'Company';
    final coAddr = app.settings.coAddr;

    // Colour palette
    const darkColor   = PdfColor.fromInt(0xFF1A1A1A);
    const accentColor = PdfColor.fromInt(0xFF2563EB);
    const greenColor  = PdfColor.fromInt(0xFF16A34A);
    const redColor    = PdfColor.fromInt(0xFFDC2626);
    const bgColor     = PdfColor.fromInt(0xFFF8F8F6);
    const mutedColor  = PdfColor.fromInt(0xFF6B7280);
    const borderColor = PdfColor.fromInt(0xFFE5E5E0);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          // Earnings rows (non-zero)
          final earnRows = _earn.where((e) {
            final amt = double.tryParse(e['amount'] ?? '0') ?? 0;
            return amt > 0 && (e['desc'] ?? '').isNotEmpty;
          }).toList();

          // Deduction rows
          final dedRows = _ded.where((d) {
            final amt = double.tryParse(d['amount'] ?? '0') ?? 0;
            return amt > 0 && (d['desc'] ?? '').isNotEmpty;
          }).toList();

          pw.Widget _tableRow(String label, String value,
              {bool bold = false, PdfColor? valueColor, bool isLast = false}) =>
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: isLast ? pw.BorderSide.none : const pw.BorderSide(color: borderColor, width: 0.5),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(label,
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                            color: bold ? darkColor : mutedColor)),
                    pw.Text(value,
                        style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                            color: valueColor ?? darkColor)),
                  ],
                ),
              );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: darkColor,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('PAYSLIP',
                          style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                              letterSpacing: 2)),
                      pw.SizedBox(height: 4),
                      pw.Text(monthLabel,
                          style: pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFF9CA3AF))),
                    ]),
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      pw.Text(coName,
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                      if (coAddr.isNotEmpty)
                        pw.Text(coAddr,
                            style: pw.TextStyle(
                                fontSize: 9,
                                color: PdfColor.fromInt(0xFF9CA3AF))),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // ── Employee info ─────────────────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: bgColor,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: borderColor),
                ),
                child: pw.Row(
                  children: [
                    // Avatar circle
                    pw.Container(
                      width: 44, height: 44,
                      decoration: pw.BoxDecoration(
                        color: accentColor,
                        shape: pw.BoxShape.circle,
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white),
                      ),
                    ),
                    pw.SizedBox(width: 14),
                    pw.Expanded(
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(emp.name,
                            style: pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: darkColor)),
                        if (emp.position.isNotEmpty)
                          pw.Text(emp.position,
                              style: pw.TextStyle(fontSize: 10, color: mutedColor)),
                        if (emp.department.isNotEmpty)
                          pw.Text(emp.department,
                              style: pw.TextStyle(fontSize: 10, color: mutedColor)),
                      ]),
                    ),
                    pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                      if (emp.icNo.isNotEmpty)
                        pw.Text('IC: ${emp.icNo}',
                            style: pw.TextStyle(fontSize: 9, color: mutedColor)),
                      if (emp.epfNo.isNotEmpty)
                        pw.Text('EPF: ${emp.epfNo}',
                            style: pw.TextStyle(fontSize: 9, color: mutedColor)),
                      if (emp.socsoNo.isNotEmpty)
                        pw.Text('SOCSO: ${emp.socsoNo}',
                            style: pw.TextStyle(fontSize: 9, color: mutedColor)),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // ── Earnings & Deductions side by side ────────────────────
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Earnings
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColor.fromInt(0xFFBBF7D0)),
                        color: PdfColor.fromInt(0xFFF0FDF4),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('EARNINGS',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: greenColor,
                                letterSpacing: 1)),
                        pw.SizedBox(height: 8),
                        ...earnRows.map((e) {
                          final amt = double.tryParse(e['amount'] ?? '0') ?? 0;
                          return _tableRow(e['desc'] ?? '', fmtMYR(amt));
                        }),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 8),
                          padding: const pw.EdgeInsets.only(top: 8),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFF86EFAC), width: 1)),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('GROSS PAY',
                                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkColor)),
                              pw.Text(fmtMYR(_gross),
                                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: greenColor)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  // Deductions
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(14),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColor.fromInt(0xFFFECACA)),
                        color: PdfColor.fromInt(0xFFFFF5F5),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text('DEDUCTIONS',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: redColor,
                                letterSpacing: 1)),
                        pw.SizedBox(height: 8),
                        if (_useEPF) _tableRow('EPF (Employee)', fmtMYR(_eeEPF)),
                        if (_useSOCSO) _tableRow('SOCSO (Employee)', fmtMYR(_eeSSO)),
                        if (_useEIS) _tableRow('EIS (Employee)', fmtMYR(_eeEIS)),
                        ...dedRows.map((d) {
                          final amt = double.tryParse(d['amount'] ?? '0') ?? 0;
                          return _tableRow(d['desc'] ?? '', fmtMYR(amt));
                        }),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 8),
                          padding: const pw.EdgeInsets.only(top: 8),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(color: PdfColor.fromInt(0xFFFCA5A5), width: 1)),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('TOTAL DED.',
                                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: darkColor)),
                              pw.Text('(${fmtMYR(_totDed)})',
                                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: redColor)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // ── Net Pay banner ────────────────────────────────────────
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: pw.BoxDecoration(
                  color: darkColor,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('NET PAY',
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                            letterSpacing: 1)),
                    pw.Text(fmtMYR(_netPay),
                        style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromInt(0xFF4ADE80))),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // ── Employer cost note ─────────────────────────────────────
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('Total employer cost: ${fmtMYR(_erCost)}',
                      style: pw.TextStyle(fontSize: 9, color: mutedColor)),
                ],
              ),

              // ── Statutory contributions breakdown ──────────────────────
              if (_useEPF || _useSOCSO || _useEIS) ...[
                pw.SizedBox(height: 14),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColor.fromInt(0xFFBFDBFE)),
                    color: PdfColor.fromInt(0xFFEFF6FF),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('STATUTORY CONTRIBUTIONS',
                        style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: accentColor,
                            letterSpacing: 1)),
                    pw.SizedBox(height: 8),
                    pw.Row(children: [
                      pw.Expanded(child: pw.Text('', style: pw.TextStyle(fontSize: 9, color: mutedColor))),
                      pw.SizedBox(width: 60, child: pw.Text('Employee', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: mutedColor))),
                      pw.SizedBox(width: 60, child: pw.Text('Employer', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: mutedColor))),
                    ]),
                    if (_useEPF) pw.Row(children: [
                      pw.Expanded(child: pw.Text('EPF', style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_eeEPF), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_erEPF), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                    ]),
                    if (_useSOCSO) pw.Row(children: [
                      pw.Expanded(child: pw.Text('SOCSO', style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_eeSSO), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_erSSO), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                    ]),
                    if (_useEIS) pw.Row(children: [
                      pw.Expanded(child: pw.Text('EIS', style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_eeEIS), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                      pw.SizedBox(width: 60, child: pw.Text(fmtMYR(_erEIS), style: pw.TextStyle(fontSize: 9, color: darkColor))),
                    ]),
                  ]),
                ),
              ],

              // ── Bank & Footer ─────────────────────────────────────────
              if (emp.bankName.isNotEmpty || emp.bankAcct.isNotEmpty) ...[
                pw.SizedBox(height: 14),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderColor),
                    color: bgColor,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(children: [
                    pw.Text('Bank Payment: ', style: pw.TextStyle(fontSize: 9, color: mutedColor)),
                    pw.Text('${emp.bankName}  ${emp.bankAcct}',
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: darkColor)),
                  ]),
                ),
              ],

              pw.Spacer(),
              pw.Divider(color: borderColor),
              pw.Text(
                'This is a computer-generated payslip. Generated on ${DateTime.now().toIso8601String().substring(0, 10)}.',
                style: pw.TextStyle(fontSize: 8, color: mutedColor),
              ),
            ],
          );
        },
      ),
    );

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

    return Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      height: MediaQuery.of(context).size.height * 0.96,
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
    );
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
