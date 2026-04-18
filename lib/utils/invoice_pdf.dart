// ─── invoice_pdf.dart ────────────────────────────────────────────────────────
// Generates a PDF Uint8List for a given invoice.
// Uses the `pdf` package (already in pubspec.yaml).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

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
  // ── Chinese font support ──────────────────────────────────────────────────
  // Load NotoSansSC from assets for proper CJK character rendering.
  // Falls back to Helvetica if the font asset is not bundled.
  pw.Font? cjkFont;
  try {
    final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjkFont = pw.Font.ttf(fontData);
  } catch (_) {
    // Font not bundled — ASCII-only mode
  }

  final pdf = pw.Document();
  final baseTheme = cjkFont != null
      ? pw.ThemeData.withFont(base: cjkFont, bold: cjkFont)
      : pw.ThemeData();

  pw.MemoryImage? logo;
  if (logoBase64 != null && logoBase64.isNotEmpty) {
    logo = pw.MemoryImage(base64Decode(logoBase64.split(',').last));
  }

  pw.MemoryImage? sig;
  if (sigBase64 != null && sigBase64.isNotEmpty) {
    sig = pw.MemoryImage(base64Decode(sigBase64.split(',').last));
  }

  // ── Calculation helpers ───────────────────────────────────────────────────
  double calcNet(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    final sub   = qty * price;
    return sub - (sub * disc / 100);
  }

  double calcSST(Map<String, String> r) {
    // Keys must exactly match constants.dart sstRates map
    const Map<String, double> sstRateMap = {
      'none':     0,
      'sst5':     0.05,
      'sst10':    0.10,
      'service6': 0.06,
      'service8': 0.08,
    };
    return calcNet(r) * (sstRateMap[r['sst'] ?? 'none'] ?? 0);
  }

  final double subtotal = rows.fold(0, (s, r) => s + calcNet(r));
  final double totalSST = rows.fold(0, (s, r) => s + calcSST(r));
  final double grand    = subtotal + totalSST;

  String fmtRM(double v) => 'RM ${v.toStringAsFixed(2)}';

  final tableData = rows.map((r) {
    final net = calcNet(r);
    final sst = calcSST(r);
    return [
      r['desc'] ?? '',
      r['qty']  ?? '1',
      fmtRM(double.tryParse(r['price'] ?? '0') ?? 0),
      (r['disc'] ?? '').isNotEmpty ? '${r['disc']}%' : '—',
      fmtRM(net),
      sst > 0 ? fmtRM(sst) : '—',
      fmtRM(net + sst),
    ];
  }).toList();

  final headerStyle = pw.TextStyle(
      fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9);
  final headerDecoration =
      pw.BoxDecoration(color: PdfColor.fromHex('#18160f'));
  final bodyStyle  = pw.TextStyle(fontSize: 9);
  final boldStyle  = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final smallGrey  = pw.TextStyle(fontSize: 9, color: PdfColors.grey600);

  pdf.addPage(
    pw.Page(
      theme: baseTheme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [

          // ── Header ──────────────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo, width: 65, height: 65, fit: pw.BoxFit.contain),
                    pw.SizedBox(height: 6),
                  ],
                  pw.Text(co.companyName,
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (co.coReg.isNotEmpty)     pw.Text('Reg: ${co.coReg}',        style: smallGrey),
                  if (co.sstRegNo.isNotEmpty)  pw.Text('SST Reg: ${co.sstRegNo}', style: smallGrey),
                  if (co.coAddr.isNotEmpty)    pw.Text(co.coAddr,                 style: smallGrey),
                  if (co.coPhone.isNotEmpty)   pw.Text('Tel: ${co.coPhone}',      style: smallGrey),
                  if (co.coEmail.isNotEmpty)   pw.Text(co.coEmail,                style: smallGrey),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(co.sstRegNo.isNotEmpty ? 'TAX INVOICE' : 'INVOICE',
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 8),
                  pw.Text('No: $invNo',    style: bodyStyle),
                  pw.Text('Date: $invDate', style: bodyStyle),
                  if (dueDate != null && dueDate.isNotEmpty)
                    pw.Text('Due: $dueDate',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.red700)),
                ],
              ),
            ],
          ),

          pw.Divider(thickness: 2, color: PdfColor.fromHex('#18160f')),
          pw.SizedBox(height: 10),

          // ── Bill To / Bank ───────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL TO',
                          style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600,
                              fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 4),
                      pw.Text(customer.name,
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      if (customer.regNo.isNotEmpty)    pw.Text('Reg: ${customer.regNo}',       style: smallGrey),
                      if (customer.sstRegNo.isNotEmpty) pw.Text('SST: ${customer.sstRegNo}',    style: smallGrey),
                      if (customer.address.isNotEmpty)  pw.Text(customer.address,               style: smallGrey),
                      if (customer.phone.isNotEmpty)    pw.Text(customer.phone,                 style: smallGrey),
                      if (customer.email.isNotEmpty)    pw.Text(customer.email,                 style: smallGrey),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              if (bankName != null && bankName.isNotEmpty)
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PAYMENT TO',
                            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600,
                                fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 4),
                        pw.Text(bankName, style: boldStyle),
                        if (bankAcct != null && bankAcct.isNotEmpty)
                          pw.Text(bankAcct, style: bodyStyle),
                        pw.Text(co.companyName, style: smallGrey),
                      ],
                    ),
                  ),
                )
              else
                pw.Expanded(child: pw.SizedBox()),
            ],
          ),

          pw.SizedBox(height: 14),

          // ── Items table ─────────────────────────────────────────────────
          pw.Table.fromTextArray(
            headerStyle: headerStyle,
            headerDecoration: headerDecoration,
            cellStyle: bodyStyle,
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1.5),
            },
            headers: ['Description', 'Qty', 'Unit Price', 'Disc%', 'Net', 'SST', 'Total'],
            data: tableData,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),

          pw.SizedBox(height: 14),

          // ── Totals ──────────────────────────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subtotal', style: bodyStyle),
                    pw.Text(fmtRM(subtotal), style: bodyStyle),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SST', style: smallGrey),
                    pw.Text(fmtRM(totalSST), style: bodyStyle),
                  ],
                ),
                pw.Divider(thickness: 2, color: PdfColor.fromHex('#18160f')),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL DUE',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.Text(fmtRM(grand),
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ]),
            ),
          ),

          pw.Spacer(),

          // ── Footer ──────────────────────────────────────────────────────
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (notes != null && notes.isNotEmpty) ...[
                      pw.Text('NOTES',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 3),
                      pw.Text(notes,
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      pw.SizedBox(height: 8),
                    ],
                    if (terms != null && terms.isNotEmpty) ...[
                      pw.Text('TERMS & CONDITIONS',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey600)),
                      pw.SizedBox(height: 3),
                      pw.Text(terms,
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    ],
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Generated by Bookly MY · ${DateTime.now().toString().substring(0, 10)}',
                      style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (sig != null)
                    pw.Image(sig, width: 120, height: 50, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(width: 120, height: 50),
                  pw.Container(
                    width: 120,
                    decoration: const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(color: PdfColors.black))),
                    child: pw.Text('Authorised Signature',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                        textAlign: pw.TextAlign.center),
                  ),
                  pw.Text(co.companyName, style: boldStyle, textAlign: pw.TextAlign.center),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}
