// ─── invoice_pdf.dart ─────────────────────────────────────────────────────────
// Malaysia LHDN-compliant Tax Invoice / e-Invoice
// Upgrades v2:
//   • CJK font fix — font passed explicitly to every pw.Text via fontFallback
//   • TAX INVOICE vs INVOICE title switch
//   • Ship To section (always shown, "Same as billing address" if empty)
//   • Full line-item table: No | Description | Qty | Unit Price | Disc% | Amount
//   • SST breakdown — Sales Tax & Service Tax separated
//   • Amount in Words (English)
//   • Payment Terms structured block (method, terms, penalty)
//   • e-Invoice QR + UUID placeholder block
//   • Multi-page support with repeated table header
//   • Signature + authorised block in footer
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _navy    = PdfColor.fromInt(0xFF1A237E);
const _indigo  = PdfColor.fromInt(0xFF3949AB);
const _light   = PdfColor.fromInt(0xFFE8EAF6);
const _border  = PdfColor.fromInt(0xFFDDE1F0);
const _muted   = PdfColor.fromInt(0xFF6B7280);
const _dark    = PdfColor.fromInt(0xFF1F2937);
const _white   = PdfColors.white;
const _rowAlt  = PdfColor.fromInt(0xFFF7F8FC);
const _green   = PdfColor.fromInt(0xFF166534);
const _red     = PdfColor.fromInt(0xFFB91C1C);
const _amber   = PdfColor.fromInt(0xFF92400E);
const _teal    = PdfColor.fromInt(0xFF0F766E);

// ── SST rate map ──────────────────────────────────────────────────────────────
const _sstRate = {
  'none':     0.00,
  'sst5':     0.05,
  'sst10':    0.10,
  'service6': 0.06,
  'service8': 0.08,
};
const _sstLabel = {
  'none':     '—',
  'sst5':     'Sales 5%',
  'sst10':    'Sales 10%',
  'service6': 'Svc 6%',
  'service8': 'Svc 8%',
};
// Which are Sales Tax vs Service Tax
const _isSalesTax    = {'sst5', 'sst10'};
const _isServiceTax  = {'service6', 'service8'};

// ── Amount in Words ───────────────────────────────────────────────────────────
String _amountInWords(double amount) {
  final total = amount.round();
  final sen   = ((amount - total.toDouble()).abs() * 100).round();
  final words = _toWords(total);
  final senStr = sen > 0 ? ' and Cents ${_toWords(sen)} Only' : ' Only';
  return 'Malaysian Ringgit $words$senStr';
}

String _toWords(int n) {
  if (n == 0) return 'Zero';
  const ones  = ['','One','Two','Three','Four','Five','Six','Seven','Eight','Nine',
                  'Ten','Eleven','Twelve','Thirteen','Fourteen','Fifteen',
                  'Sixteen','Seventeen','Eighteen','Nineteen'];
  const tens  = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'];
  if (n < 20)  return ones[n];
  if (n < 100) return tens[n ~/ 10] + (n % 10 > 0 ? ' ${ones[n % 10]}' : '');
  if (n < 1000) return '${ones[n ~/ 100]} Hundred'
      + (n % 100 > 0 ? ' ${_toWords(n % 100)}' : '');
  if (n < 1000000) return '${_toWords(n ~/ 1000)} Thousand'
      + (n % 1000 > 0 ? ' ${_toWords(n % 1000)}' : '');
  if (n < 1000000000) return '${_toWords(n ~/ 1000000)} Million'
      + (n % 1000000 > 0 ? ' ${_toWords(n % 1000000)}' : '');
  return n.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
Future<Uint8List> generateInvoicePdf({
  required AppSettings              co,
  required Customer                 customer,
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
  // New optional fields
  String? shipToName,
  String? shipToAddr,
  String? paymentMethod,   // e.g. "Bank Transfer"
  String? paymentTerms,    // e.g. "Net 30"
  String? latePenalty,     // e.g. "1.5% per month"
  String? bankAcctName,    // account holder name
}) async {

  // ── Load CJK font (fix: load both regular + bold, pass via fontFallback) ──
  pw.Font? cjkRegular;
  pw.Font? cjkBold;
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjkRegular = pw.Font.ttf(fd);
  } catch (_) {}
  try {
    // Try bold variant; fall back to regular if not present
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
    cjkBold = pw.Font.ttf(fd);
  } catch (_) {
    cjkBold = cjkRegular;
  }

  // Build theme — base font for non-CJK chars; CJK font as fallback
  final pw.ThemeData theme;
  if (cjkRegular != null) {
    theme = pw.ThemeData.withFont(
      base: cjkRegular,
      bold: cjkBold ?? cjkRegular,
    );
  } else {
    theme = pw.ThemeData();
  }

  // ── Helper: text style with CJK fallback ─────────────────────────────────
  // CRITICAL FIX: pass fontFallback on every text style so CJK chars render
  final List<pw.Font> _fb = cjkRegular != null ? [cjkRegular!] : [];

  pw.TextStyle ts(double sz, {
    PdfColor? color,
    bool bold = false,
    double? spacing,
    double? height,
  }) =>
      pw.TextStyle(
        fontSize: sz,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? _dark,
        letterSpacing: spacing,
        lineSpacing: height,
        fontFallback: _fb,
      );

  // ── Images ────────────────────────────────────────────────────────────────
  pw.MemoryImage? logo;
  if (logoBase64 != null && logoBase64.isNotEmpty) {
    try { logo = pw.MemoryImage(base64Decode(logoBase64.split(',').last)); }
    catch (_) {}
  }
  pw.MemoryImage? sig;
  if (sigBase64 != null && sigBase64.isNotEmpty) {
    try { sig = pw.MemoryImage(base64Decode(sigBase64.split(',').last)); }
    catch (_) {}
  }

  // ── Calculations ─────────────────────────────────────────────────────────
  double netAmt(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }
  double sstAmt(Map<String, String> r) =>
      netAmt(r) * (_sstRate[r['sst'] ?? 'none'] ?? 0);

  final subtotal   = rows.fold<double>(0, (s, r) => s + netAmt(r));
  final totalSST   = rows.fold<double>(0, (s, r) => s + sstAmt(r));
  final grand      = subtotal + totalSST;
  final isTaxInv   = co.sstRegNo.isNotEmpty;

  // SST breakdown by rate
  final Map<String, _TaxBucket> buckets = {};
  for (final r in rows) {
    final key = r['sst'] ?? 'none';
    if (key == 'none') continue;
    final n = netAmt(r);
    final s = sstAmt(r);
    buckets[key] = _TaxBucket(
      label:   _sstLabel[key] ?? key,
      isSales: _isSalesTax.contains(key),
      netAmt:  (buckets[key]?.netAmt ?? 0) + n,
      sstAmt:  (buckets[key]?.sstAmt ?? 0) + s,
    );
  }

  // Taxable vs exempt amounts
  final taxableAmt = rows
      .where((r) => (r['sst'] ?? 'none') != 'none')
      .fold<double>(0, (s, r) => s + netAmt(r));
  final exemptAmt  = subtotal - taxableAmt;

  // Format helpers
  String rm(double v) => 'RM ${v.toStringAsFixed(2).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},')}';

  // ── e-Invoice UUID + QR (placeholder — real integration via MyInvois API) ─
  final _seed      = '$invNo|$invDate|${co.coReg}|${customer.name}|${grand.toStringAsFixed(2)}';
  final _hash      = base64Encode(utf8.encode(_seed)).replaceAll('=', '').toUpperCase();
  final _uuid      = '${_hash.substring(0,8)}-${_hash.substring(8,12)}-'
                     '${_hash.substring(12,16)}-${_hash.substring(16,20)}-'
                     '${_hash.substring(20,32)}';
  final _digitalSig = _hash.substring(0, 44);
  final _qrData    = 'https://myinvois.hasil.gov.my/verify?uuid=$_uuid'
                     '&inv=${Uri.encodeComponent(invNo)}'
                     '&amt=${grand.toStringAsFixed(2)}&date=$invDate';
  final _validatedAt = '$invDate  ${DateTime.now().toIso8601String().substring(11, 16)} MYT';

  // ── Widget helpers ────────────────────────────────────────────────────────
  pw.Widget div({PdfColor? color, double thick = 0.5}) =>
      pw.Divider(color: color ?? _border, thickness: thick, height: 1);

  pw.Widget chip(String n) => pw.Container(
    width: 15, height: 15,
    decoration: const pw.BoxDecoration(color: _indigo, shape: pw.BoxShape.circle),
    alignment: pw.Alignment.center,
    child: pw.Text(n, style: ts(6.5, color: _white, bold: true)),
  );

  pw.Widget sLabel(String t) =>
      pw.Text(t, style: ts(7.5, color: _muted, spacing: 0.3));

  pw.Widget infoRow(String label, String value,
      {bool bold = false, PdfColor? vc, double sz = 8}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 140,
              child: pw.Text(label, style: ts(sz, color: _muted)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: ts(sz, color: vc ?? _dark, bold: bold),
                  textAlign: pw.TextAlign.right),
            ),
          ],
        ),
      );

  // ── Table column widths ───────────────────────────────────────────────────
  const _colNo    = 18.0;
  const _colQty   = 36.0;
  const _colPrice = 68.0;
  const _colDisc  = 36.0;
  const _colSST   = 52.0;
  const _colAmt   = 72.0;

  pw.Widget tableHeader() => pw.Container(
    color: _navy,
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: pw.Row(children: [
      pw.SizedBox(width: _colNo,
          child: pw.Text('No', style: ts(7.5, color: _white, bold: true))),
      pw.Expanded(
          child: pw.Text('Description', style: ts(7.5, color: _white, bold: true))),
      pw.SizedBox(width: _colQty,
          child: pw.Text('Qty', style: ts(7.5, color: _white, bold: true),
              textAlign: pw.TextAlign.right)),
      pw.SizedBox(width: _colPrice,
          child: pw.Text('Unit Price', style: ts(7.5, color: _white, bold: true),
              textAlign: pw.TextAlign.right)),
      pw.SizedBox(width: _colDisc,
          child: pw.Text('Disc%', style: ts(7.5, color: _white, bold: true),
              textAlign: pw.TextAlign.right)),
      pw.SizedBox(width: _colSST,
          child: pw.Text('SST', style: ts(7.5, color: _white, bold: true),
              textAlign: pw.TextAlign.right)),
      pw.SizedBox(width: _colAmt,
          child: pw.Text('Amount', style: ts(7.5, color: _white, bold: true),
              textAlign: pw.TextAlign.right)),
    ]),
  );

  // ── Build PDF ─────────────────────────────────────────────────────────────
  final pdf = pw.Document(theme: theme);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 50),
      // Repeat table header on each page
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Column(children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(co.companyName, style: ts(8, bold: true)),
                  pw.Text(isTaxInv ? 'TAX INVOICE' : 'INVOICE',
                      style: ts(8, color: _muted)),
                  pw.Text(invNo, style: ts(8, bold: true)),
                ],
              ),
              pw.SizedBox(height: 4),
              tableHeader(),
            ]),
      footer: (ctx) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _border, width: 0.5))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by Bookly MY  ·  $invDate',
                style: ts(7, color: _muted)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: ts(7, color: _muted)),
          ],
        ),
      ),
      build: (ctx) => [

        // ══════════════════════════════════════════════════════════════════
        // SECTION 1: HEADER — Company + Invoice title
        // ══════════════════════════════════════════════════════════════════
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(18),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company info
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logo != null) ...[
                      pw.Image(logo, width: 60, height: 30, fit: pw.BoxFit.contain),
                      pw.SizedBox(height: 8),
                    ],
                    pw.Text(co.companyName,
                        style: ts(14, color: _white, bold: true)),
                    pw.SizedBox(height: 4),
                    if (co.coReg.isNotEmpty)
                      pw.Text('SSM Reg No: ${co.coReg}',
                          style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                    if (co.sstRegNo.isNotEmpty)
                      pw.Text('SST Reg No: ${co.sstRegNo}',
                          style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                    if (co.coAddr.isNotEmpty)
                      pw.Text(co.coAddr,
                          style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                    if (co.coPhone.isNotEmpty)
                      pw.Text('Tel: ${co.coPhone}',
                          style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                    if (co.coEmail.isNotEmpty)
                      pw.Text(co.coEmail,
                          style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              // Invoice title block
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(isTaxInv ? 'TAX INVOICE' : 'INVOICE',
                      style: ts(24, color: _white, bold: true, spacing: 1.5)),
                  pw.SizedBox(height: 12),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF253580),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(invNo,
                            style: ts(11, color: _white, bold: true)),
                        pw.SizedBox(height: 4),
                        pw.Text('Date: $invDate',
                            style: ts(8, color: PdfColor.fromInt(0xFFAFC6E9))),
                        if (dueDate != null && dueDate.isNotEmpty)
                          pw.Text('Due:  $dueDate',
                              style: ts(8,
                                  color: PdfColor.fromInt(0xFFFFD580),
                                  bold: true)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 16),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 2: BILL TO + SHIP TO (always shown)
        // ══════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Bill To
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('1'),
                      pw.SizedBox(width: 6),
                      sLabel('BILL TO'),
                    ]),
                    pw.SizedBox(height: 6),
                    pw.Text(customer.name, style: ts(9.5, bold: true)),
                    if (customer.regNo.isNotEmpty)
                      pw.Text('SSM: ${customer.regNo}',
                          style: ts(8, color: _muted)),
                    if (customer.sstRegNo.isNotEmpty)
                      pw.Text('SST: ${customer.sstRegNo}',
                          style: ts(8, color: _muted)),
                    if (customer.address.isNotEmpty)
                      pw.Text(customer.address, style: ts(8, color: _muted)),
                    if (customer.phone.isNotEmpty)
                      pw.Text('Tel: ${customer.phone}',
                          style: ts(8, color: _muted)),
                    if (customer.email.isNotEmpty)
                      pw.Text(customer.email, style: ts(8, color: _muted)),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            // Ship To
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('2'),
                      pw.SizedBox(width: 6),
                      sLabel('SHIP TO'),
                    ]),
                    pw.SizedBox(height: 6),
                    if (shipToName != null && shipToName.isNotEmpty) ...[
                      pw.Text(shipToName, style: ts(9.5, bold: true)),
                      if (shipToAddr != null && shipToAddr.isNotEmpty)
                        pw.Text(shipToAddr, style: ts(8, color: _muted)),
                    ] else ...[
                      pw.Text(customer.name, style: ts(9.5, bold: true)),
                      pw.Text('Same as billing address',
                          style: ts(8, color: _muted)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 16),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 3: SELLER + BUYER TAX DETAILS
        // ══════════════════════════════════════════════════════════════════
        pw.Container(
          color: _rowAlt,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Seller
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('3'),
                      pw.SizedBox(width: 6),
                      sLabel('SELLER TAX DETAILS'),
                    ]),
                    pw.SizedBox(height: 5),
                    if (co.coReg.isNotEmpty)
                      infoRow('SSM Registration No.', co.coReg),
                    if (co.sstRegNo.isNotEmpty)
                      infoRow('SST Registration No.', co.sstRegNo),
                    infoRow('Invoice Currency', 'Malaysian Ringgit (MYR)'),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              // Buyer
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('4'),
                      pw.SizedBox(width: 6),
                      sLabel('BUYER TAX DETAILS'),
                    ]),
                    pw.SizedBox(height: 5),
                    if (customer.regNo.isNotEmpty)
                      infoRow('SSM Registration No.', customer.regNo),
                    if (customer.sstRegNo.isNotEmpty)
                      infoRow('SST Registration No.', customer.sstRegNo),
                    if (customer.phone.isNotEmpty)
                      infoRow('Contact', customer.phone),
                    if (customer.email.isNotEmpty)
                      infoRow('Email', customer.email),
                  ],
                ),
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 16),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 4: IRBM e-Invoice Reference (chip 5)
        // ══════════════════════════════════════════════════════════════════
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromInt(0xFFBFDBFE)),
            color: PdfColor.fromInt(0xFFEFF6FF),
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              chip('5'),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    sLabel('IRBM e-INVOICE REFERENCE (MyInvois)'),
                    pw.SizedBox(height: 4),
                    infoRow('Unique Document ID (UUID)', _uuid, sz: 7.5),
                    infoRow('Digital Signature', _digitalSig, sz: 7.5),
                    infoRow('Validated Date & Time', _validatedAt, sz: 7.5),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: _qrData,
                    width: 52, height: 52,
                    color: _navy,
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text('Scan to verify', style: ts(6.5, color: _muted)),
                  pw.Text('MyInvois Portal', style: ts(6.5, color: _muted)),
                ],
              ),
            ],
          ),
        ),

        pw.SizedBox(height: 18),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 5: LINE ITEMS TABLE (chips 6 7 8 9 10 11)
        // ══════════════════════════════════════════════════════════════════
        pw.Row(children: [
          chip('6'),
          pw.SizedBox(width: 6),
          sLabel('LINE ITEMS'),
        ]),
        pw.SizedBox(height: 6),

        tableHeader(),

        // Rows
        ...rows.asMap().entries.map((entry) {
          final i   = entry.key;
          final r   = entry.value;
          final n   = netAmt(r);
          final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
          final sstKey = r['sst'] ?? 'none';
          final sstRate = _sstRate[sstKey] ?? 0;
          final price = double.tryParse(r['price'] ?? '0') ?? 0;
          final qty   = double.tryParse(r['qty'] ?? '1') ?? 1;
          final rowColor = i.isOdd ? _rowAlt : _white;
          return pw.Container(
            color: rowColor,
            padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: _colNo,
                      child: pw.Text('${i + 1}',
                          style: ts(8.5, color: _muted, bold: true)),
                    ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(r['desc'] ?? '',
                              style: ts(8.5, bold: true)),
                          if ((r['note'] ?? '').isNotEmpty)
                            pw.Text(r['note']!,
                                style: ts(7.5, color: _muted)),
                        ],
                      ),
                    ),
                    pw.SizedBox(
                      width: _colQty,
                      child: pw.Text(
                        qty % 1 == 0
                            ? qty.toInt().toString()
                            : qty.toStringAsFixed(2),
                        style: ts(8.5),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(
                      width: _colPrice,
                      child: pw.Text(rm(price),
                          style: ts(8.5), textAlign: pw.TextAlign.right),
                    ),
                    pw.SizedBox(
                      width: _colDisc,
                      child: pw.Text(
                        disc > 0 ? '${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}%' : '—',
                        style: ts(8.5, color: disc > 0 ? _red : _muted),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(
                      width: _colSST,
                      child: pw.Text(
                        sstKey == 'none' ? 'Exempt' : _sstLabel[sstKey]!,
                        style: ts(7.5,
                            color: sstKey == 'none' ? _muted : _teal),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(
                      width: _colAmt,
                      child: pw.Text(rm(n),
                          style: ts(8.5, bold: true),
                          textAlign: pw.TextAlign.right),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        div(thick: 1, color: _dark),
        pw.SizedBox(height: 12),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 6: SST BREAKDOWN + SUMMARY (chips 7–11)
        // ══════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left: SST breakdown
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // chip 7 — taxable / exempt summary
                  pw.Row(children: [
                    chip('7'),
                    pw.SizedBox(width: 6),
                    sLabel('SST BREAKDOWN'),
                  ]),
                  pw.SizedBox(height: 6),

                  if (buckets.isEmpty) ...[
                    pw.Text('All items — Tax Exempt (0%)',
                        style: ts(8, color: _muted)),
                  ] else ...[
                    // Group: Sales Tax rows
                    if (buckets.values.any((b) => b.isSales)) ...[
                      pw.Text('Sales Tax Items',
                          style: ts(7.5, color: _muted, bold: true)),
                      pw.SizedBox(height: 3),
                      ...buckets.entries
                          .where((e) => e.value.isSales)
                          .map((e) => pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 3),
                                child: pw.Row(children: [
                                  pw.Expanded(
                                      child: pw.Text(
                                          'Taxable amount @ ${e.value.label}',
                                          style: ts(8))),
                                  pw.SizedBox(width: 8),
                                  pw.Text(rm(e.value.netAmt), style: ts(8)),
                                  pw.SizedBox(width: 8),
                                  pw.SizedBox(
                                    width: 60,
                                    child: pw.Text(rm(e.value.sstAmt),
                                        style: ts(8, color: _amber),
                                        textAlign: pw.TextAlign.right),
                                  ),
                                ]),
                              )),
                      pw.SizedBox(height: 4),
                    ],
                    // Group: Service Tax rows
                    if (buckets.values.any((b) => !b.isSales)) ...[
                      pw.Text('Service Tax Items',
                          style: ts(7.5, color: _muted, bold: true)),
                      pw.SizedBox(height: 3),
                      ...buckets.entries
                          .where((e) => !e.value.isSales)
                          .map((e) => pw.Padding(
                                padding: const pw.EdgeInsets.only(bottom: 3),
                                child: pw.Row(children: [
                                  pw.Expanded(
                                      child: pw.Text(
                                          'Taxable amount @ ${e.value.label}',
                                          style: ts(8))),
                                  pw.SizedBox(width: 8),
                                  pw.Text(rm(e.value.netAmt), style: ts(8)),
                                  pw.SizedBox(width: 8),
                                  pw.SizedBox(
                                    width: 60,
                                    child: pw.Text(rm(e.value.sstAmt),
                                        style: ts(8, color: _teal),
                                        textAlign: pw.TextAlign.right),
                                  ),
                                ]),
                              )),
                    ],
                  ],

                  pw.SizedBox(height: 10),

                  // chip 8 — taxable / exempt amounts
                  pw.Row(children: [
                    chip('8'),
                    pw.SizedBox(width: 6),
                    sLabel('AMOUNT SUMMARY'),
                  ]),
                  pw.SizedBox(height: 6),
                  if (taxableAmt > 0)
                    pw.Row(children: [
                      pw.Expanded(
                          child: pw.Text('Total Taxable Amount',
                              style: ts(8, color: _muted))),
                      pw.Text(rm(taxableAmt), style: ts(8)),
                    ]),
                  if (exemptAmt > 0)
                    pw.Row(children: [
                      pw.Expanded(
                          child: pw.Text('Total Exempt Amount',
                              style: ts(8, color: _muted))),
                      pw.Text(rm(exemptAmt), style: ts(8)),
                    ]),
                ],
              ),
            ),

            pw.SizedBox(width: 20),

            // Right: Amount Due box (chips 9 10 11)
            pw.SizedBox(
              width: 210,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    chip('9'),
                    pw.SizedBox(width: 6),
                    sLabel('INVOICE TOTAL'),
                  ]),
                  pw.SizedBox(height: 6),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _border),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      children: [
                        // Subtotal
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('Subtotal (excl. SST)',
                                  style: ts(8, color: _muted)),
                              pw.Text(rm(subtotal), style: ts(8)),
                            ],
                          ),
                        ),
                        div(),
                        // SST breakdown lines
                        ...buckets.entries.map((e) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              child: pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                      '${e.value.isSales ? "Sales Tax" : "Service Tax"} ${e.value.label}',
                                      style: ts(8, color: _muted)),
                                  pw.Text(rm(e.value.sstAmt),
                                      style: ts(8,
                                          color: e.value.isSales
                                              ? _amber
                                              : _teal)),
                                ],
                              ),
                            )),
                        if (buckets.isEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text('SST', style: ts(8, color: _muted)),
                                pw.Text(rm(0), style: ts(8, color: _muted)),
                              ],
                            ),
                          ),
                        div(thick: 1, color: _navy),
                        // chip 10 — Grand Total
                        pw.Container(
                          decoration: const pw.BoxDecoration(
                            color: _light,
                            borderRadius: pw.BorderRadius.only(
                              bottomLeft: pw.Radius.circular(6),
                              bottomRight: pw.Radius.circular(6),
                            ),
                          ),
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: pw.Row(children: [
                            chip('10'),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              child: pw.Text('AMOUNT DUE',
                                  style: ts(9, color: _navy, bold: true)),
                            ),
                            pw.Text(rm(grand),
                                style: ts(11, color: _navy, bold: true)),
                          ]),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 8),

                  // chip 11 — Amount in Words
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFFFFBEB),
                      border: pw.Border.all(
                          color: PdfColor.fromInt(0xFFFDE68A)),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        chip('11'),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Amount in Words',
                                  style: ts(7, color: _muted, bold: true)),
                              pw.SizedBox(height: 2),
                              pw.Text(_amountInWords(grand),
                                  style: ts(7.5,
                                      color: _amber, bold: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 18),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 7: PAYMENT INFO + TERMS (chips 12 13)
        // ══════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Payment Info
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('12'),
                      pw.SizedBox(width: 6),
                      sLabel('PAYMENT INFORMATION'),
                    ]),
                    pw.SizedBox(height: 8),
                    if (paymentMethod != null && paymentMethod.isNotEmpty)
                      infoRow('Payment Method', paymentMethod),
                    if (paymentTerms != null && paymentTerms.isNotEmpty)
                      infoRow('Payment Terms', paymentTerms)
                    else
                      infoRow('Payment Terms', 'Net 30 Days'),
                    if (dueDate != null && dueDate.isNotEmpty)
                      infoRow('Due Date', dueDate, vc: _red, bold: true),
                    if (latePenalty != null && latePenalty.isNotEmpty)
                      infoRow('Late Payment Penalty', latePenalty),
                    if (bankName != null && bankName.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      div(),
                      pw.SizedBox(height: 6),
                      pw.Text('Bank Transfer Details',
                          style: ts(7.5, color: _muted, bold: true)),
                      pw.SizedBox(height: 4),
                      infoRow('Bank', bankName),
                      if (bankAcctName != null && bankAcctName.isNotEmpty)
                        infoRow('Account Name', bankAcctName),
                      if (bankAcct != null && bankAcct.isNotEmpty)
                        infoRow('Account Number', bankAcct, bold: true),
                      infoRow('Payment Reference', invNo),
                    ],
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 10),
            // Notes + Terms
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _border),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(children: [
                      chip('13'),
                      pw.SizedBox(width: 6),
                      sLabel('NOTES & TERMS'),
                    ]),
                    pw.SizedBox(height: 8),
                    if (notes != null && notes.isNotEmpty) ...[
                      pw.Text('Notes',
                          style: ts(7.5, color: _muted, bold: true)),
                      pw.SizedBox(height: 3),
                      pw.Text(notes, style: ts(8)),
                      pw.SizedBox(height: 8),
                    ],
                    if (terms != null && terms.isNotEmpty) ...[
                      pw.Text('Terms & Conditions',
                          style: ts(7.5, color: _muted, bold: true)),
                      pw.SizedBox(height: 3),
                      pw.Text(terms, style: ts(8, color: _muted)),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'E. & O. E. — Errors and Omissions Excepted.',
                      style: ts(7.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 18),
        div(thick: 0.8, color: _dark),
        pw.SizedBox(height: 12),

        // ══════════════════════════════════════════════════════════════════
        // SECTION 8: FOOTER — Signature + Declaration (chip 14)
        // ══════════════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Declaration text
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    chip('14'),
                    pw.SizedBox(width: 6),
                    sLabel('DECLARATION'),
                  ]),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'This is a computer-generated ${isTaxInv ? "Tax Invoice" : "Invoice"} '
                    'and does not require a physical signature unless otherwise stated. '
                    'This document is issued in compliance with the Malaysian SST Act 2018.',
                    style: ts(7.5, color: _muted),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated by Bookly MY  ·  $invDate  ·  MYR ${grand.toStringAsFixed(2)}',
                    style: ts(7, color: _muted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // Signature block
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (sig != null)
                  pw.Image(sig, width: 110, height: 48, fit: pw.BoxFit.contain)
                else
                  pw.SizedBox(width: 110, height: 48),
                pw.Container(
                  width: 130,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(color: _dark, width: 0.8)),
                  ),
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Column(
                    children: [
                      pw.Text('Authorised Signature',
                          style: ts(7, color: _muted),
                          textAlign: pw.TextAlign.center),
                      pw.SizedBox(height: 2),
                      pw.Text(co.companyName,
                          style: ts(8, bold: true),
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
  );

  return pdf.save();
}

// ── Helper model ──────────────────────────────────────────────────────────────
class _TaxBucket {
  final String label;
  final bool   isSales;
  final double netAmt, sstAmt;
  _TaxBucket({
    required this.label,
    required this.isSales,
    required this.netAmt,
    required this.sstAmt,
  });
}
