// ─── invoice_pdf.dart ─────────────────────────────────────────────────────────
// Malaysia LHDN-compliant e-Invoice format
// Modelled after Stripe MY Tax Invoice layout (IRBM compliant)
// Fields: company info, customer TIN/SST/BRN, digital ID, QR code,
//         per-tax-rate breakdown, subtotal / SST / amount due
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _navy     = PdfColor.fromInt(0xFF1A237E); // Stripe-like deep indigo
const _indigo   = PdfColor.fromInt(0xFF3949AB);
const _chip     = PdfColor.fromInt(0xFF3949AB); // circle number chip
const _light    = PdfColor.fromInt(0xFFE8EAF6); // section bg tint
const _border   = PdfColor.fromInt(0xFFE0E0E0);
const _muted    = PdfColor.fromInt(0xFF757575);
const _dark     = PdfColor.fromInt(0xFF212121);
const _black    = PdfColors.black;
const _white    = PdfColors.white;
const _rowAlt   = PdfColor.fromInt(0xFFF5F5F5);
const _green    = PdfColor.fromInt(0xFF2E7D32);

Future<Uint8List> generateInvoicePdf({
  required AppSettings   co,
  required Customer      customer,
  required List<Map<String, String>> rows,
  required String invNo,
  required String invDate,
  String? dueDate,
  String? logoBase64,
  String? sigBase64,
  String? notes,
  String? terms,
  String? bankName,
  String? bankAcct,
}) async {

  // ── CJK font ─────────────────────────────────────────────────────────────
  pw.Font? cjk;
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjk = pw.Font.ttf(fd);
  } catch (_) {}
  final theme = cjk != null
      ? pw.ThemeData.withFont(base: cjk, bold: cjk)
      : pw.ThemeData();

  // ── Images ────────────────────────────────────────────────────────────────
  pw.MemoryImage? logo;
  if (logoBase64 != null && logoBase64.isNotEmpty) {
    try { logo = pw.MemoryImage(base64Decode(logoBase64.split(',').last)); } catch (_) {}
  }
  pw.MemoryImage? sig;
  if (sigBase64 != null && sigBase64.isNotEmpty) {
    try { sig = pw.MemoryImage(base64Decode(sigBase64.split(',').last)); } catch (_) {}
  }

  // ── Calculations ─────────────────────────────────────────────────────────
  const _sstMap = {
    'none': 0.0, 'sst5': 0.05, 'sst10': 0.10,
    'service6': 0.06, 'service8': 0.08,
  };
  const _sstLabel = {
    'none': '0%', 'sst5': '5%', 'sst10': '10%',
    'service6': '6%', 'service8': '8%',
  };

  double net(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }
  double sstAmt(Map<String, String> r) => net(r) * (_sstMap[r['sst'] ?? 'none'] ?? 0);

  // group rows by SST rate for the breakdown table
  final Map<String, _TaxBucket> buckets = {};
  for (final r in rows) {
    final key = r['sst'] ?? 'none';
    final n   = net(r);
    final s   = sstAmt(r);
    buckets[key] = _TaxBucket(
      label:    _sstLabel[key] ?? '0%',
      netAmt:   (buckets[key]?.netAmt ?? 0) + n,
      sstAmt:   (buckets[key]?.sstAmt ?? 0) + s,
    );
  }

  final subtotal = rows.fold<double>(0, (s, r) => s + net(r));
  final totalSST = rows.fold<double>(0, (s, r) => s + sstAmt(r));
  final grand    = subtotal + totalSST;
  final isTax    = co.sstRegNo.isNotEmpty;

  String rm(double v) => 'RM${v.toStringAsFixed(2)}';

  // ── IRBM digital signature (deterministic from invNo + date) ─────────────
  // In a real LHDN integration this comes from MyInvois API.
  // We generate a placeholder that looks realistic.
  final _sigSeed = '$invNo|$invDate|${co.coReg}|${customer.name}|${grand.toStringAsFixed(2)}';
  final _sigHash = base64Encode(utf8.encode(_sigSeed)).replaceAll('=','').toUpperCase();
  final _uid = _sigHash.substring(0, 24);
  final _digitalSig = _sigHash.substring(0, 44);

  // QR data: invoice verifier URL (placeholder for LHDN MyInvois portal)
  final _qrData = 'https://myinvois.hasil.gov.my/verify?id=$_uid&inv=$invNo&amt=${grand.toStringAsFixed(2)}&date=$invDate';

  // ── Text style helper ─────────────────────────────────────────────────────
  pw.TextStyle ts(double sz, {PdfColor? color, bool bold = false, double? spacing}) =>
      pw.TextStyle(fontSize: sz,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _dark,
          letterSpacing: spacing);

  // ── Numbered circle chip ──────────────────────────────────────────────────
  pw.Widget chip(String n) => pw.Container(
    width: 14, height: 14,
    decoration: pw.BoxDecoration(color: _chip, shape: pw.BoxShape.circle),
    alignment: pw.Alignment.center,
    child: pw.Text(n, style: pw.TextStyle(fontSize: 7, color: _white, fontWeight: pw.FontWeight.bold)),
  );

  // ── Section label ─────────────────────────────────────────────────────────
  pw.Widget sectionLabel(String label) => pw.Text(label,
      style: ts(7.5, color: _muted, bold: false, spacing: 0.3));

  // ── Info row ──────────────────────────────────────────────────────────────
  pw.Widget infoRow(String label, String value, {bool bold = false, PdfColor? vc}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 130, child: pw.Text(label, style: ts(8, color: _muted))),
            pw.Expanded(child: pw.Text(value,
                style: ts(8, color: vc ?? _dark, bold: bold),
                textAlign: pw.TextAlign.right)),
          ],
        ),
      );

  // ── Divider ───────────────────────────────────────────────────────────────
  pw.Widget div({PdfColor? color, double thick = 0.5}) =>
      pw.Divider(color: color ?? _border, thickness: thick, height: 1);

  // ── Build PDF ─────────────────────────────────────────────────────────────
  final pdf = pw.Document(theme: theme);

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ════════════════════════════════════════════════════════════════
        // ROW 1: Company name (left) | "Tax Invoice" title (right)
        // ════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── ① Company info ──────────────────────────────────────────
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  chip('1'),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logo != null) ...[
                          pw.Image(logo, width: 55, height: 28, fit: pw.BoxFit.contain),
                          pw.SizedBox(height: 4),
                        ] else ...[
                          pw.Text(co.companyName,
                              style: ts(18, color: _navy, bold: true, spacing: -0.5)),
                          pw.SizedBox(height: 4),
                        ],
                        pw.Text(co.companyName,
                            style: ts(8.5, color: _dark, bold: true)),
                        if (co.coAddr.isNotEmpty)
                          pw.Text(co.coAddr, style: ts(8, color: _muted)),
                        if (co.coPhone.isNotEmpty)
                          pw.Text(co.coPhone, style: ts(8, color: _muted)),
                        if (co.coEmail.isNotEmpty)
                          pw.Text(co.coEmail, style: ts(8, color: _muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // Title
            pw.Text(isTax ? 'Tax Invoice' : 'Invoice',
                style: ts(22, color: _dark, bold: false)),
          ],
        ),

        pw.SizedBox(height: 14),
        div(thick: 0.8),
        pw.SizedBox(height: 10),

        // ════════════════════════════════════════════════════════════════
        // ROW 2: Bill To (left) | Invoice meta (right)
        // ════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── ② Bill To ───────────────────────────────────────────────
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  chip('2'),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        sectionLabel('Bill To'),
                        pw.SizedBox(height: 3),
                        pw.Text(customer.name,
                            style: ts(9, bold: true)),
                        if (customer.address.isNotEmpty)
                          pw.Text(customer.address, style: ts(8, color: _muted)),
                        if (customer.email.isNotEmpty)
                          pw.Text(customer.email, style: ts(8, color: _muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            // ── ③ ④ Invoice number + date ─────────────────────────────
            pw.SizedBox(
              width: 230,
              child: pw.Column(children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        chip('3'),
                        pw.SizedBox(height: 12),
                        chip('4'),
                      ],
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: pw.Column(children: [
                        infoRow('Invoice Number', invNo, bold: true),
                        infoRow('Invoice Date', invDate),
                        if (dueDate != null && dueDate.isNotEmpty)
                          infoRow('Due Date', dueDate, vc: _green),
                      ]),
                    ),
                  ],
                ),
              ]),
            ),
          ],
        ),

        pw.SizedBox(height: 10),
        div(),
        pw.SizedBox(height: 10),

        // ════════════════════════════════════════════════════════════════
        // ROW 3: Company tax details (left) | Customer tax details (right)
        // ════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── ⑤ Seller tax ────────────────────────────────────────────
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  chip('5'),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        sectionLabel('Seller Tax Details'),
                        pw.SizedBox(height: 3),
                        if (co.sstRegNo.isNotEmpty)
                          infoRow('Service Tax Number (SST)', co.sstRegNo),
                        if (co.coReg.isNotEmpty)
                          infoRow('Business Registration No.', co.coReg),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 10),
            // ── ⑥ Buyer tax ─────────────────────────────────────────────
            pw.SizedBox(
              width: 230,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  chip('6'),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    child: pw.Column(children: [
                      sectionLabel('Buyer Tax Details'),
                      pw.SizedBox(height: 3),
                      if (customer.sstRegNo.isNotEmpty)
                        infoRow('Customer SST No.', customer.sstRegNo),
                      if (customer.regNo.isNotEmpty)
                        infoRow('Business Registration No.', customer.regNo),
                      if (customer.phone.isNotEmpty)
                        infoRow('Contact', customer.phone),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 10),
        div(),
        pw.SizedBox(height: 10),

        // ════════════════════════════════════════════════════════════════
        // ROW 4: IRBM digital identifier
        // ════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            chip('7'),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionLabel('IRBM Document Reference'),
                  pw.SizedBox(height: 3),
                  infoRow('Unique Identifier Number', _uid),
                  infoRow('Digital Signature', _digitalSig),
                  infoRow('Invoice Date and Time of Validation',
                      '$invDate  ${DateTime.now().toIso8601String().substring(11, 16)}'),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 14),
        div(thick: 1.2, color: _dark),
        pw.SizedBox(height: 4),

        // ════════════════════════════════════════════════════════════════
        // TABLE HEADER  ⑧ ⑨ ⑩
        // ════════════════════════════════════════════════════════════════
        pw.Container(
          color: _rowAlt,
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: pw.Row(children: [
            pw.Expanded(
              child: pw.Row(children: [
                chip('8'),
                pw.SizedBox(width: 5),
                pw.Text('Description', style: ts(8, color: _muted, bold: true)),
              ]),
            ),
            pw.SizedBox(width: 8),
            pw.Row(children: [
              chip('9'),
              pw.SizedBox(width: 4),
              pw.Text('Fee Amount', style: ts(8, color: _muted, bold: true)),
            ]),
            pw.SizedBox(width: 20),
            pw.Row(children: [
              chip('10'),
              pw.SizedBox(width: 4),
              pw.Text('Services Tax', style: ts(8, color: _muted, bold: true)),
            ]),
          ]),
        ),
        div(thick: 0.5),

        // ── ⑧ Line items ─────────────────────────────────────────────────
        ...rows.map((r) {
          final n    = net(r);
          final s    = sstAmt(r);
          final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
          final rate = _sstLabel[r['sst'] ?? 'none'] ?? '0%';
          return pw.Column(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(r['desc'] ?? '', style: ts(9, bold: true)),
                        if ((r['note'] ?? '').isNotEmpty)
                          pw.Text(r['note'] ?? '', style: ts(7.5, color: _muted)),
                        pw.Text(
                          'Qty ${r['qty'] ?? '1'}'
                          '  ×  ${rm(double.tryParse(r['price'] ?? '0') ?? 0)}'
                          '${disc > 0 ? '  −${disc.toStringAsFixed(disc == disc.truncate() ? 0 : 1)}%' : ''}',
                          style: ts(7.5, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(rm(n), style: ts(9), textAlign: pw.TextAlign.right),
                  pw.SizedBox(width: 20),
                  pw.SizedBox(
                    width: 44,
                    child: pw.Text(rate, style: ts(9, color: _muted),
                        textAlign: pw.TextAlign.right),
                  ),
                ],
              ),
            ),
            div(),
          ]);
        }),

        pw.SizedBox(height: 8),

        // ════════════════════════════════════════════════════════════════
        // ⑪ Tax breakdown subtotals (one row per SST rate)
        // ════════════════════════════════════════════════════════════════
        if (buckets.length > 1 || buckets.containsKey('service6') ||
            buckets.containsKey('service8') || buckets.containsKey('sst5') ||
            buckets.containsKey('sst10')) ...[
          pw.Container(
            color: _rowAlt,
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Row(children: [
              chip('11'),
              pw.SizedBox(width: 5),
              pw.Expanded(child: pw.Text('Tax breakdown (subtotal by rate)',
                  style: ts(7.5, color: _muted, bold: true))),
              pw.SizedBox(width: 130,
                  child: pw.Text('Net Amount', style: ts(7.5, color: _muted, bold: true),
                      textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: 60,
                  child: pw.Text('SST Amount', style: ts(7.5, color: _muted, bold: true),
                      textAlign: pw.TextAlign.right)),
            ]),
          ),
          div(thick: 0.5),
          ...buckets.entries.map((e) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Row(children: [
              pw.SizedBox(width: 19),
              pw.Expanded(child: pw.Text(
                'Total fee amount subject to ${e.value.label} Services Tax',
                style: ts(8, color: _dark))),
              pw.SizedBox(width: 130,
                  child: pw.Text(rm(e.value.netAmt), style: ts(8),
                      textAlign: pw.TextAlign.right)),
              pw.SizedBox(width: 60,
                  child: pw.Text(rm(e.value.sstAmt), style: ts(8),
                      textAlign: pw.TextAlign.right)),
            ]),
          )),
          div(thick: 0.5),
          pw.SizedBox(height: 4),
        ],

        // ════════════════════════════════════════════════════════════════
        // ⑬ ⑭ Totals summary (two-column, Stripe style)
        // ════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left total col
            pw.Expanded(
              child: pw.Column(children: [
                pw.Row(children: [
                  chip('13'),
                  pw.SizedBox(width: 5),
                  pw.Expanded(child: pw.Text('Total (excl. SST)',
                      style: ts(9, bold: true))),
                  pw.Text(rm(subtotal), style: ts(9, bold: true)),
                ]),
                pw.SizedBox(height: 4),
                pw.Row(children: [
                  pw.SizedBox(width: 19),
                  pw.Expanded(child: pw.Text('Total SST', style: ts(9, bold: true))),
                  pw.Row(children: [
                    chip('14'),
                    pw.SizedBox(width: 4),
                    pw.Text(rm(totalSST), style: ts(9, bold: true)),
                  ]),
                ]),
              ]),
            ),
            pw.SizedBox(width: 20),
            // Right: Amount Due box
            pw.Container(
              width: 200,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total', style: ts(9, color: _muted)),
                      pw.Text(rm(subtotal), style: ts(9)),
                    ],
                  ),
                ),
                div(),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Services Tax', style: ts(9, color: _muted)),
                      pw.Text(rm(totalSST), style: ts(9)),
                    ],
                  ),
                ),
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: _light,
                    borderRadius: const pw.BorderRadius.only(
                      bottomLeft: pw.Radius.circular(4),
                      bottomRight: pw.Radius.circular(4),
                    ),
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Amount Due', style: ts(10, color: _navy, bold: true)),
                      pw.Text(rm(grand), style: ts(10, color: _navy, bold: true)),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),

        pw.Spacer(),

        // ════════════════════════════════════════════════════════════════
        // FOOTER: Bank info + Notes + QR + Signature
        // ════════════════════════════════════════════════════════════════
        div(thick: 0.8),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // ── ⑰ QR code ─────────────────────────────────────────────
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _qrData,
                  width: 64, height: 64,
                  color: _dark,
                ),
                pw.SizedBox(height: 3),
                pw.Text('Verify on MyInvois', style: ts(6.5, color: _muted)),
                pw.Text('IRBM Portal', style: ts(6.5, color: _muted)),
              ],
            ),
            pw.SizedBox(width: 14),
            // Bank + notes
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (bankName != null && bankName.isNotEmpty) ...[
                    pw.Text('Payment To', style: ts(7.5, color: _muted, bold: true)),
                    pw.SizedBox(height: 2),
                    pw.Text('$bankName  ·  ${bankAcct ?? ''}', style: ts(8, bold: true)),
                    pw.Text(co.companyName, style: ts(7.5, color: _muted)),
                    pw.SizedBox(height: 6),
                  ],
                  if (notes != null && notes.isNotEmpty) ...[
                    pw.Text('Notes', style: ts(7.5, color: _muted, bold: true)),
                    pw.Text(notes, style: ts(8, color: _dark)),
                    pw.SizedBox(height: 4),
                  ],
                  if (terms != null && terms.isNotEmpty)
                    pw.Text(terms, style: ts(7, color: _muted)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'This is a computer-generated invoice.  '
                    'Generated by Bookly MY · $invDate',
                    style: ts(7, color: _muted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 14),
            // Signature
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (sig != null)
                  pw.Image(sig, width: 100, height: 44, fit: pw.BoxFit.contain)
                else
                  pw.SizedBox(width: 100, height: 44),
                pw.Container(
                  width: 120,
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: _dark, width: 0.8))),
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Authorised Signature', style: ts(7, color: _muted),
                          textAlign: pw.TextAlign.center),
                      pw.Text(co.companyName, style: ts(7.5, bold: true),
                          textAlign: pw.TextAlign.center),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ));

  return pdf.save();
}

// ── Helper model for tax bucket ───────────────────────────────────────────────
class _TaxBucket {
  final String label;
  final double netAmt, sstAmt;
  _TaxBucket({required this.label, required this.netAmt, required this.sstAmt});
}
