import 'package:intl/intl.dart';
import 'constants.dart';
import 'models.dart';

// ─── Formatters ───────────────────────────────────────────────────────────────
String fmtMYR(double n) {
  try {
    final f = NumberFormat('#,##0.00', 'en_MY');
    return 'RM ${f.format(n.abs())}';
  } catch (_) {
    return 'RM ${n.abs().toStringAsFixed(2)}';
  }
}

String fmtShort(double n) {
  final abs = n.abs();
  if (abs >= 1000) return 'RM ${(abs / 1000).toStringAsFixed(1)}k';
  return fmtMYR(n);
}

String fmtDate(String iso, String lang) {
  try {
    final d = DateTime.parse('${iso}T12:00:00');
    final locale = lang == 'zh' ? 'zh_MY' : 'en_MY';
    return DateFormat('d MMM', locale).format(d);
  } catch (_) {
    return iso.length >= 10 ? iso.substring(5, 10) : iso;
  }
}

String fmtDateFull(String iso, String lang) {
  final d = DateTime.parse('${iso}T12:00:00');
  return DateFormat('EEE, d MMM').format(d);
}

String fmtMonthLabel(String ym, String lang) {
  final d = DateTime.parse('$ym-01');
  return DateFormat(lang == 'zh' ? 'yyyy年 MMMM' : 'MMMM yyyy').format(d);
}

String nowISO() => DateTime.now().toIso8601String().substring(0, 10);

int nowTs() => DateTime.now().millisecondsSinceEpoch;

// ─── Invoice HTML (opens in browser / PDF printer) ────────────────────────────
String genInvoiceHTML({
  required AppSettings co,
  required Customer customer,
  String? logoBase64,
  String? sigBase64,
  required String invNo,
  required String invDate,
  String? dueDate,
  required List<Map<String, dynamic>> rows,
  String? notes,
  String? terms,
  String? bankName,
  String? bankAcct,
}) {
  double calcNet(Map r) {
    final sub = (num.tryParse(r['qty']?.toString() ?? '1') ?? 1).toDouble() *
                (num.tryParse(r['price']?.toString() ?? '0') ?? 0).toDouble();
    final disc = sub * ((num.tryParse(r['disc']?.toString() ?? '0') ?? 0).toDouble() / 100);
    return sub - disc;
  }
  double calcSST(Map r) => calcNet(r) * (sstRates[r['sst'] ?? 'none']?.rate ?? 0);

  final subtotal = rows.fold<double>(0, (s, r) => s + calcNet(r));
  final totalSST = rows.fold<double>(0, (s, r) => s + calcSST(r));
  final grand    = subtotal + totalSST;
  final isTax    = co.sstRegNo.isNotEmpty;

  String f(double n) => 'RM ${n.toStringAsFixed(2).replaceAllMapped(RegExp(r'\\B(?=(\\d{3})+(?!\\d))'), (_) => ',')}';

  return '''<!DOCTYPE html><html><head><meta charset="utf-8"/>
<title>${isTax ? 'TAX INVOICE' : 'INVOICE'} $invNo</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Arial,sans-serif;font-size:13px;color:#18160f;padding:32px;max-width:800px;margin:0 auto}
.hdr{display:grid;grid-template-columns:1fr auto;gap:20px;border-bottom:3px solid #18160f;padding-bottom:16px;margin-bottom:16px}
.title{font-size:28px;font-weight:900;text-align:right;letter-spacing:-1px}
.parties{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:16px}
.box{border:1px solid #e8e4de;border-radius:8px;padding:12px}
.lbl{font-size:10px;color:#9b9084;text-transform:uppercase;letter-spacing:.5px;margin-bottom:5px;font-weight:700}
table{width:100%;border-collapse:collapse;margin-bottom:8px}
th{background:#18160f;color:#fff;padding:9px 10px;font-size:11px;text-transform:uppercase;letter-spacing:.4px;text-align:left}
th:nth-child(n+2){text-align:right}
td{padding:9px 10px;border-bottom:1px solid #f5f4f0}
td:nth-child(n+2){text-align:right}
.tot{float:right;width:260px;margin-top:8px}
.tr{display:flex;justify-content:space-between;padding:5px 0;border-bottom:1px solid #f5f4f0}
.gr{display:flex;justify-content:space-between;padding:11px 0 4px;font-size:16px;font-weight:900;border-top:3px solid #18160f;margin-top:3px}
.foot{clear:both;margin-top:24px;display:grid;grid-template-columns:1fr 1fr;gap:16px;border-top:1px solid #e8e4de;padding-top:14px}
@media print{body{padding:16px}}
</style></head><body>
<div class="hdr">
<div>
${logoBase64 != null ? '<img src="$logoBase64" style="height:65px;object-fit:contain;display:block;margin-bottom:8px"/>' : ''}
<div style="font-size:20px;font-weight:900">${co.companyName}</div>
${co.coReg.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">Reg: ${co.coReg}</div>' : ''}
${co.sstRegNo.isNotEmpty ? '<div style="font-size:11px;color:#9b9084;font-weight:700">SST Reg: ${co.sstRegNo}</div>' : ''}
${co.coAddr.isNotEmpty ? '<div style="font-size:11px;color:#9b9084;margin-top:3px">${co.coAddr.replaceAll('\n', '<br/>')}</div>' : ''}
${co.coPhone.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">Tel: ${co.coPhone}</div>' : ''}
${co.coEmail.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">${co.coEmail}</div>' : ''}
</div>
<div>
<div class="title">${isTax ? 'TAX INVOICE' : 'INVOICE'}</div>
<div style="text-align:right;margin-top:10px;font-size:12px">
<div style="margin-bottom:3px"><span style="color:#9b9084">Invoice No: </span><strong>$invNo</strong></div>
<div style="margin-bottom:3px"><span style="color:#9b9084">Date: </span><strong>$invDate</strong></div>
${dueDate != null && dueDate.isNotEmpty ? '<div style="color:#b91c1c"><span style="color:#9b9084">Due: </span><strong>$dueDate</strong></div>' : ''}
</div></div></div>
<div class="parties">
<div class="box"><div class="lbl">Bill To</div>
<div style="font-size:14px;font-weight:800;margin-bottom:3px">${customer.name}</div>
${customer.regNo.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">Reg: ${customer.regNo}</div>' : ''}
${customer.sstRegNo.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">SST Reg: ${customer.sstRegNo}</div>' : ''}
${customer.address.isNotEmpty ? '<div style="font-size:11px;color:#9b9084;margin-top:3px">${customer.address.replaceAll('\n', '<br/>')}</div>' : ''}
${customer.phone.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">${customer.phone}</div>' : ''}
${customer.email.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">${customer.email}</div>' : ''}
</div>
${(bankName?.isNotEmpty == true || bankAcct?.isNotEmpty == true) ? '''
<div class="box"><div class="lbl">Payment To</div>
<div style="font-weight:700;font-size:13px">${bankName ?? ''}</div>
<div style="font-size:13px">${bankAcct ?? ''}</div>
<div style="font-size:11px;color:#9b9084">${co.companyName}</div></div>
''' : '<div></div>'}
</div>
<table>
<thead><tr><th>Description</th><th>Qty</th><th>Unit Price</th><th>Disc%</th><th>Net</th><th>SST</th><th>Total</th></tr></thead>
<tbody>
${rows.asMap().entries.map((e) {
  final r = e.value; final i = e.key;
  final net = calcNet(r); final sst = calcSST(r);
  return '<tr style="background:${i%2==1 ? '#fafafa' : '#fff'}">'
    '<td><div style="font-weight:600">${r['desc'] ?? ''}</div>${(r['note'] ?? '').isNotEmpty ? '<div style="font-size:11px;color:#9b9084">${r['note']}</div>' : ''}</td>'
    '<td>${r['qty'] ?? 1}</td>'
    '<td>${f((num.tryParse(r['price']?.toString() ?? '0') ?? 0).toDouble())}</td>'
    '<td>${(r['disc'] ?? '').toString().isNotEmpty ? '${r['disc']}%' : '—'}</td>'
    '<td>${f(net)}</td>'
    '<td>${sst > 0 ? f(sst) : '—'}</td>'
    '<td style="font-weight:700">${f(net + sst)}</td>'
    '</tr>';
}).join('\n')}
</tbody></table>
<div class="tot">
<div class="tr"><span>Subtotal</span><span>${f(subtotal)}</span></div>
<div class="tr"><span style="color:#9b9084">SST</span><span>${f(totalSST)}</span></div>
<div class="gr"><span>TOTAL DUE</span><span>${f(grand)}</span></div>
</div>
<div class="foot">
<div>
${notes != null && notes.isNotEmpty ? '<div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:#9b9084;margin-bottom:5px">Notes</div><div style="font-size:12px;color:#475569;line-height:1.5">${notes.replaceAll('\n', '<br/>')}</div>' : ''}
${terms != null && terms.isNotEmpty ? '<div style="font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:#9b9084;margin:10px 0 5px">Terms & Conditions</div><div style="font-size:11px;color:#475569;line-height:1.5">${terms.replaceAll('\n', '<br/>')}</div>' : ''}
<div style="font-size:10px;color:#9b9084;margin-top:10px">Generated by Bookly MY · ${DateTime.now().toString().substring(0, 10)}</div>
</div>
<div style="text-align:center">
${sigBase64 != null ? '<img src="$sigBase64" style="height:55px;object-fit:contain;display:block;width:100%;border-bottom:1px solid #18160f;margin-bottom:5px"/>' : '<div style="height:55px;border-bottom:1px solid #18160f;margin-bottom:5px"></div>'}
<div style="font-size:10px;color:#9b9084">Authorised Signature</div>
<div style="font-size:12px;font-weight:700">${co.companyName}</div>
</div></div>
</body></html>''';
}

// ─── Payslip HTML ─────────────────────────────────────────────────────────────
const _months = ['January','February','March','April','May','June','July','August','September','October','November','December'];

String genPayslipHTML({
  required AppSettings co,
  String? logoBase64,
  required Employee emp,
  required int month,
  required int year,
  required List<Map<String,String>> payItems,
  required List<Map<String,String>> deductions,
  required bool useEPF,
  required bool useSOCSO,
  required bool useEIS,
}) {
  final gross    = payItems.fold<double>(0, (s,p) => s + (double.tryParse(p['amount']??'0')??0));
  final otherDed = deductions.fold<double>(0, (s,d) => s + (double.tryParse(d['amount']??'0')??0));
  final eeEPF    = useEPF   ? epfEe(gross)   : 0.0;
  final erEPF    = useEPF   ? epfEr(gross)   : 0.0;
  final eeSSO    = useSOCSO ? socsoEe(gross)  : 0.0;
  final erSSO    = useSOCSO ? socsoEr(gross)  : 0.0;
  final eeEIS    = useEIS   ? eisEe(gross)    : 0.0;
  final erEIS    = useEIS   ? eisEr(gross)    : 0.0;
  final totDed   = otherDed + eeEPF + eeSSO + eeEIS;
  final netPay   = gross - totDed;
  final erCost   = gross + erEPF + erSSO + erEIS;

  String f(double n) => 'RM ${n.toStringAsFixed(2)}';

  return '''<!DOCTYPE html><html><head><meta charset="utf-8"/>
<title>Payslip ${emp.name} ${_months[month-1]} $year</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:Arial,sans-serif;font-size:13px;color:#18160f;padding:32px;max-width:720px;margin:0 auto}
.hdr{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid #18160f;padding-bottom:14px;margin-bottom:14px}
.badge{background:#18160f;color:#fff;font-size:20px;font-weight:900;padding:7px 16px;border-radius:7px}
.g2{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:14px}
.box{border:1px solid #e8e4de;border-radius:7px;padding:12px}
.lbl{font-size:10px;color:#9b9084;text-transform:uppercase;letter-spacing:.4px;margin-bottom:3px;font-weight:700}
table{width:100%;border-collapse:collapse;margin-bottom:14px}
th{background:#f5f4f0;padding:8px 10px;font-size:11px;text-transform:uppercase;letter-spacing:.4px;color:#9b9084;text-align:left}
th:last-child{text-align:right}
td{padding:8px 10px;border-bottom:1px solid #f5f4f0}
td:last-child{text-align:right;font-weight:600}
.net{background:#18160f;color:#fff;padding:14px;border-radius:8px;display:flex;justify-content:space-between;align-items:center}
.note{font-size:10px;color:#9b9084;text-align:center;border-top:1px solid #e8e4de;padding-top:10px;margin-top:16px}
@media print{body{padding:16px}}
</style></head><body>
<div class="hdr">
<div>
${logoBase64 != null ? '<img src="$logoBase64" style="height:55px;object-fit:contain;display:block;margin-bottom:6px"/>' : ''}
<div style="font-size:18px;font-weight:900">${co.companyName}</div>
${co.coReg.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">Reg: ${co.coReg}</div>' : ''}
${co.coAddr.isNotEmpty ? '<div style="font-size:11px;color:#9b9084;margin-top:2px">${co.coAddr.replaceAll('\n','<br/>')}</div>' : ''}
</div>
<div style="text-align:right">
<div class="badge">PAYSLIP</div>
<div style="margin-top:8px;font-size:12px;color:#9b9084">${_months[month-1]} $year</div>
<div style="font-size:11px;color:#9b9084">Pay Date: ${DateTime.now().toString().substring(0,10)}</div>
</div></div>
<div class="g2">
<div class="box"><div class="lbl">Employee</div>
<div style="font-weight:800;font-size:14px">${emp.name}</div>
${emp.icNo.isNotEmpty ? '<div style="font-size:11px;color:#9b9084">IC: ${emp.icNo}</div>' : ''}
${emp.position.isNotEmpty ? '<div style="font-size:12px;color:#9b9084">${emp.position}${emp.department.isNotEmpty ? ' · ${emp.department}' : ''}</div>' : ''}
</div>
<div class="box"><div class="lbl">Statutory & Bank</div>
${emp.epfNo.isNotEmpty ? '<div style="font-size:11px">EPF: ${emp.epfNo}</div>' : ''}
${emp.socsoNo.isNotEmpty ? '<div style="font-size:11px">SOCSO: ${emp.socsoNo}</div>' : ''}
${emp.bankName.isNotEmpty ? '<div style="font-size:12px;font-weight:600;margin-top:4px">${emp.bankName}</div>' : ''}
${emp.bankAcct.isNotEmpty ? '<div style="font-size:12px">${emp.bankAcct}</div>' : ''}
</div></div>
<table><thead><tr><th>Earnings</th><th>Amount</th></tr></thead><tbody>
${payItems.where((p)=>(double.tryParse(p['amount']??'0')??0)>0).map((p)=>'<tr><td>${p['desc']}</td><td>${f(double.tryParse(p['amount']??'0')??0)}</td></tr>').join('\n')}
<tr style="font-weight:700"><td>Gross Pay</td><td>${f(gross)}</td></tr>
</tbody></table>
<table><thead><tr><th>Deductions</th><th>Employee</th><th style="text-align:right">Employer</th></tr></thead><tbody>
${deductions.where((d)=>(double.tryParse(d['amount']??'0')??0)>0).map((d)=>'<tr><td>${d['desc']}</td><td>${f(double.tryParse(d['amount']??'0')??0)}</td><td>—</td></tr>').join('\n')}
${useEPF ? '<tr><td>EPF</td><td>${f(eeEPF)}</td><td style="text-align:right">${f(erEPF)}</td></tr>' : ''}
${useSOCSO ? '<tr><td>SOCSO</td><td>${f(eeSSO)}</td><td style="text-align:right">${f(erSSO)}</td></tr>' : ''}
${useEIS ? '<tr><td>EIS</td><td>${f(eeEIS)}</td><td style="text-align:right">${f(erEIS)}</td></tr>' : ''}
</tbody></table>
<div class="net">
<div><div style="font-size:12px;color:#6b6860">NET PAY</div></div>
<div style="font-size:24px;font-weight:900;color:#4ade80;font-family:Georgia,serif">${f(netPay)}</div>
</div>
<div style="text-align:right;font-size:11px;color:#9b9084;margin-top:6px">Employer total cost: ${f(erCost)}</div>
<div class="note">Computer-generated payslip · Bookly MY · ${DateTime.now().toString().substring(0,10)}</div>
</body></html>''';
}
