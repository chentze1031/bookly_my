// ─── invoice_pdf.dart ─────────────────────────────────────────────────────────
// Malaysia-style professional Tax Invoice / Commercial Invoice
// Layout inspired by SQL Accounting, AutoCount, and LHDN-compliant formats
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

// ── Brand colours (can be swapped per company) ────────────────────────────────
const _kPrimary   = PdfColor.fromInt(0xFF1B3A6B); // deep navy  – professional MY look
const _kAccent    = PdfColor.fromInt(0xFFE8600A); // amber-orange highlight
const _kDark      = PdfColor.fromInt(0xFF0F1F3D); // near-black navy
const _kHeaderBg  = PdfColor.fromInt(0xFF1B3A6B);
const _kRowAlt    = PdfColor.fromInt(0xFFF2F5FA); // alternating row tint
const _kBorder    = PdfColor.fromInt(0xFFD0D8E8);
const _kMuted     = PdfColor.fromInt(0xFF64748B);
const _kGreen     = PdfColor.fromInt(0xFF16A34A);
const _kRed       = PdfColor.fromInt(0xFFDC2626);

Future<Uint8List> generateInvoicePdf({
  required AppSettings co,
  required Customer customer,
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

  // ── Font (CJK support) ───────────────────────────────────────────────────
  pw.Font? cjkFont;
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjkFont = pw.Font.ttf(fd);
  } catch (_) {}
  final theme = cjkFont != null
      ? pw.ThemeData.withFont(base: cjkFont, bold: cjkFont)
      : pw.ThemeData();

  // ── Logo / signature images ──────────────────────────────────────────────
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
    'none': 0.0, 'sst5': 0.05, 'sst10': 0.10, 'service6': 0.06, 'service8': 0.08,
  };

  double _net(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }
  double _sst(Map<String, String> r) => _net(r) * (_sstMap[r['sst'] ?? 'none'] ?? 0);

  final subtotal = rows.fold<double>(0, (s, r) => s + _net(r));
  final totalSST = rows.fold<double>(0, (s, r) => s + _sst(r));
  final grand    = subtotal + totalSST;
  final hasSst   = totalSST > 0;
  final isTax    = co.sstRegNo.isNotEmpty;
  final docTitle = isTax ? 'TAX INVOICE' : 'INVOICE';

  String rm(double v) => 'RM ${v.toStringAsFixed(2)}';

  // ── Text styles ───────────────────────────────────────────────────────────
  pw.TextStyle ts(double sz, {PdfColor? color, bool bold = false}) =>
      pw.TextStyle(fontSize: sz,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _kDark);

  // ── Build page ───────────────────────────────────────────────────────────
  final pdf = pw.Document(theme: theme);

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.zero,
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ╔══════════════════════════════════════════════════════════════╗
        // ║  TOP HEADER BAND  (navy background)                         ║
        // ╚══════════════════════════════════════════════════════════════╝
        pw.Container(
          color: _kHeaderBg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 22),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Left: logo + company info
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logo != null) ...[
                      pw.Container(
                        width: 56, height: 56,
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(width: 14),
                    ],
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(co.companyName,
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white)),
                        if (co.coReg.isNotEmpty)
                          pw.Text('Co. Reg: ${co.coReg}',
                              style: ts(8, color: PdfColor.fromInt(0xFFABBDD4))),
                        if (co.sstRegNo.isNotEmpty)
                          pw.Text('SST Reg: ${co.sstRegNo}',
                              style: ts(8, color: PdfColor.fromInt(0xFFABBDD4))),
                        if (co.coPhone.isNotEmpty)
                          pw.Text('Tel: ${co.coPhone}',
                              style: ts(8, color: PdfColor.fromInt(0xFFABBDD4))),
                        if (co.coEmail.isNotEmpty)
                          pw.Text(co.coEmail,
                              style: ts(8, color: PdfColor.fromInt(0xFFABBDD4))),
                      ],
                    ),
                  ],
                ),
              ),
              // Right: doc type + accent band
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: _kAccent,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(docTitle,
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white, letterSpacing: 1.5)),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(invNo,
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                  pw.SizedBox(height: 3),
                  pw.Text('Date: $invDate',
                      style: ts(9, color: PdfColor.fromInt(0xFFABBDD4))),
                  if (dueDate != null && dueDate.isNotEmpty)
                    pw.Text('Due: $dueDate',
                        style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFFFFB347),
                            fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),

        // ── Company address bar ──────────────────────────────────────────
        if (co.coAddr.isNotEmpty)
          pw.Container(
            color: _kDark,
            padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 5),
            child: pw.Text(co.coAddr.replaceAll('\n', '  ·  '),
                style: ts(8, color: PdfColor.fromInt(0xFF8AA3C0))),
          ),

        // ── Body content (padded) ────────────────────────────────────────
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 18, 36, 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [

                // ── Bill To / Payment Info row ───────────────────────────
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Bill To box
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: _kRowAlt,
                          border: pw.Border.all(color: _kBorder),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Container(
                              margin: const pw.EdgeInsets.only(bottom: 6),
                              child: pw.Text('BILL TO',
                                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold,
                                      color: _kPrimary, letterSpacing: 1.2)),
                            ),
                            pw.Text(customer.name,
                                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _kDark)),
                            if (customer.regNo.isNotEmpty)
                              pw.Text('Reg: ${customer.regNo}', style: ts(8, color: _kMuted)),
                            if (customer.sstRegNo.isNotEmpty)
                              pw.Text('SST No: ${customer.sstRegNo}', style: ts(8, color: _kMuted)),
                            if (customer.address.isNotEmpty) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(customer.address, style: ts(8, color: _kMuted)),
                            ],
                            if (customer.phone.isNotEmpty)
                              pw.Text('Tel: ${customer.phone}', style: ts(8, color: _kMuted)),
                            if (customer.email.isNotEmpty)
                              pw.Text(customer.email, style: ts(8, color: _kMuted)),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    // Payment / bank info box
                    pw.Expanded(
                      flex: 2,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(12),
                        decoration: pw.BoxDecoration(
                          color: _kRowAlt,
                          border: pw.Border.all(color: _kBorder),
                          borderRadius: pw.BorderRadius.circular(6),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('PAYMENT DETAILS',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold,
                                    color: _kPrimary, letterSpacing: 1.2)),
                            pw.SizedBox(height: 6),
                            if (bankName != null && bankName.isNotEmpty) ...[
                              pw.Text('Bank', style: ts(7, color: _kMuted)),
                              pw.Text(bankName, style: ts(9, bold: true)),
                              pw.SizedBox(height: 4),
                            ],
                            if (bankAcct != null && bankAcct.isNotEmpty) ...[
                              pw.Text('Account No.', style: ts(7, color: _kMuted)),
                              pw.Text(bankAcct, style: ts(9, bold: true)),
                              pw.SizedBox(height: 4),
                            ],
                            pw.Text('Payable To', style: ts(7, color: _kMuted)),
                            pw.Text(co.companyName, style: ts(9, bold: true)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),

                // ── Items table ──────────────────────────────────────────
                // Header row
                pw.Container(
                  decoration: pw.BoxDecoration(
                    color: _kPrimary,
                    borderRadius: const pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(6),
                      topRight: pw.Radius.circular(6),
                    ),
                  ),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: pw.Row(children: [
                    pw.Expanded(flex: 4, child: pw.Text('DESCRIPTION',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white, letterSpacing: 0.8))),
                    pw.SizedBox(width: 60, child: pw.Text('QTY',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white), textAlign: pw.TextAlign.center)),
                    pw.SizedBox(width: 70, child: pw.Text('UNIT PRICE',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white), textAlign: pw.TextAlign.right)),
                    pw.SizedBox(width: 48, child: pw.Text('DISC',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white), textAlign: pw.TextAlign.right)),
                    if (hasSst)
                      pw.SizedBox(width: 60, child: pw.Text('SST',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white), textAlign: pw.TextAlign.right)),
                    pw.SizedBox(width: 70, child: pw.Text('AMOUNT',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white), textAlign: pw.TextAlign.right)),
                  ]),
                ),
                // Data rows
                ...rows.asMap().entries.map((entry) {
                  final i   = entry.key;
                  final r   = entry.value;
                  final net = _net(r);
                  final sst = _sst(r);
                  final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
                  final isAlt = i % 2 == 1;
                  return pw.Container(
                    color: isAlt ? _kRowAlt : PdfColors.white,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(flex: 4, child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(r['desc'] ?? '', style: ts(9, bold: true)),
                            if ((r['note'] ?? '').isNotEmpty)
                              pw.Text(r['note'] ?? '', style: ts(8, color: _kMuted)),
                          ],
                        )),
                        pw.SizedBox(width: 60, child: pw.Text(r['qty'] ?? '1',
                            style: ts(9), textAlign: pw.TextAlign.center)),
                        pw.SizedBox(width: 70, child: pw.Text(
                            rm(double.tryParse(r['price'] ?? '0') ?? 0),
                            style: ts(9), textAlign: pw.TextAlign.right)),
                        pw.SizedBox(width: 48, child: pw.Text(
                            disc > 0 ? '${disc.toStringAsFixed(disc == disc.truncate() ? 0 : 1)}%' : '—',
                            style: ts(9, color: disc > 0 ? _kRed : _kMuted),
                            textAlign: pw.TextAlign.right)),
                        if (hasSst)
                          pw.SizedBox(width: 60, child: pw.Text(
                              sst > 0 ? rm(sst) : '—',
                              style: ts(9, color: sst > 0 ? _kMuted : _kMuted),
                              textAlign: pw.TextAlign.right)),
                        pw.SizedBox(width: 70, child: pw.Text(rm(net + sst),
                            style: ts(9, bold: true), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  );
                }),
                // Table bottom border
                pw.Container(
                  height: 2,
                  color: _kPrimary,
                ),
                pw.SizedBox(height: 10),

                // ── Totals block (right-aligned) ─────────────────────────
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Notes / terms on the left
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (notes != null && notes.isNotEmpty) ...[
                            pw.Text('NOTES', style: pw.TextStyle(
                                fontSize: 8, fontWeight: pw.FontWeight.bold,
                                color: _kPrimary, letterSpacing: 0.8)),
                            pw.SizedBox(height: 3),
                            pw.Text(notes, style: ts(8, color: _kMuted)),
                            pw.SizedBox(height: 8),
                          ],
                          if (terms != null && terms.isNotEmpty) ...[
                            pw.Text('TERMS & CONDITIONS', style: pw.TextStyle(
                                fontSize: 8, fontWeight: pw.FontWeight.bold,
                                color: _kPrimary, letterSpacing: 0.8)),
                            pw.SizedBox(height: 3),
                            pw.Text(terms, style: ts(8, color: _kMuted)),
                          ],
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 20),
                    // Totals box
                    pw.Container(
                      width: 210,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _kBorder),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(children: [
                        _totalRow('Subtotal', rm(subtotal), ts(9), ts(9)),
                        if (hasSst) ...[
                          pw.Divider(color: _kBorder, height: 1),
                          _totalRow('SST', rm(totalSST), ts(9, color: _kMuted), ts(9, color: _kMuted)),
                        ],
                        pw.Container(
                          decoration: pw.BoxDecoration(
                            color: _kPrimary,
                            borderRadius: const pw.BorderRadius.only(
                              bottomLeft: pw.Radius.circular(5),
                              bottomRight: pw.Radius.circular(5),
                            ),
                          ),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('TOTAL DUE',
                                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white)),
                              pw.Text(rm(grand),
                                  style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white)),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
                pw.Spacer(),

                // ── Footer ───────────────────────────────────────────────
                pw.Divider(color: _kBorder),
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    // Left: generated note
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('This is a computer-generated document.',
                              style: ts(7, color: _kMuted)),
                          pw.Text(
                            'Generated by Bookly MY  ·  ${DateTime.now().toIso8601String().substring(0, 10)}',
                            style: ts(7, color: _kMuted),
                          ),
                        ],
                      ),
                    ),
                    // Right: signature block
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (sig != null)
                          pw.Image(sig, width: 110, height: 45, fit: pw.BoxFit.contain)
                        else
                          pw.SizedBox(width: 110, height: 45),
                        pw.Container(
                          width: 140,
                          decoration: const pw.BoxDecoration(
                              border: pw.Border(top: pw.BorderSide(color: _kDark, width: 1))),
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text('Authorised Signature',
                                  style: ts(7, color: _kMuted),
                                  textAlign: pw.TextAlign.center),
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
                pw.SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // ── Bottom accent strip ──────────────────────────────────────────
        pw.Container(
          height: 6,
          color: _kAccent,
        ),
      ],
    ),
  ));

  return pdf.save();
}

// ── Helper: one totals row ────────────────────────────────────────────────────
pw.Widget _totalRow(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: labelStyle),
          pw.Text(value, style: valueStyle),
        ],
      ),
    );
