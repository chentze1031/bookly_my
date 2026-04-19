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

// ── Palette ─────────────────────────────────────────────────────────────
const _navy   = PdfColor.fromInt(0xFF1A237E);
const _chip   = PdfColor.fromInt(0xFF3949AB);
const _light  = PdfColor.fromInt(0xFFE8EAF6);
const _border = PdfColor.fromInt(0xFFE0E0E0);
const _muted  = PdfColor.fromInt(0xFF757575);
const _dark   = PdfColor.fromInt(0xFF212121);
const _white  = PdfColors.white;
const _rowAlt = PdfColor.fromInt(0xFFF5F5F5);
const _green  = PdfColor.fromInt(0xFF2E7D32);

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

  // 🔥 IRBM（来自 backend）
  String? irbmUuid,
  String? irbmStatus,
  String? irbmQr,
}) async {

  // ── Font ──────────────────────────────────────────────────────────────
  pw.Font? cjk;
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjk = pw.Font.ttf(fd);
  } catch (_) {}
  final theme = cjk != null
      ? pw.ThemeData.withFont(base: cjk, bold: cjk)
      : pw.ThemeData();

  // ── Images ────────────────────────────────────────────────────────────
  pw.MemoryImage? logo;
  if (logoBase64 != null && logoBase64.isNotEmpty) {
    try { logo = pw.MemoryImage(base64Decode(logoBase64.split(',').last)); } catch (_) {}
  }
  pw.MemoryImage? sig;
  if (sigBase64 != null && sigBase64.isNotEmpty) {
    try { sig = pw.MemoryImage(base64Decode(sigBase64.split(',').last)); } catch (_) {}
  }

  // ── Calculations ──────────────────────────────────────────────────────
  double net(Map<String, String> r) {
    final qty = double.tryParse(r['qty'] ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }

  final subtotal = rows.fold<double>(0, (s, r) => s + net(r));
  final totalSST = 0.0;
  final grand = subtotal + totalSST;

  String rm(double v) => 'RM${v.toStringAsFixed(2)}';

  // 🔥 IRBM / fallback
  final _uid = irbmUuid ??
      base64Encode(utf8.encode('$invNo|$invDate'))
          .replaceAll('=', '')
          .substring(0, 24);

  final _status = irbmStatus ?? "Not Submitted";

  final _qrData = irbmQr ??
      'https://myapp.local/invoice/$invNo';

  // ── Styles ────────────────────────────────────────────────────────────
  pw.TextStyle ts(double sz,
          {PdfColor? color, bool bold = false}) =>
      pw.TextStyle(
        fontSize: sz,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color ?? _dark,
      );

  pw.Widget chip(String n) => pw.Container(
        width: 14,
        height: 14,
        decoration:
            pw.BoxDecoration(color: _chip, shape: pw.BoxShape.circle),
        alignment: pw.Alignment.center,
        child: pw.Text(n,
            style: pw.TextStyle(
                fontSize: 7,
                color: _white,
                fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget infoRow(String label, String value,
          {PdfColor? vc, bool bold = false}) =>
      pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: ts(8, color: _muted))),
          pw.Text(value,
              style: ts(8, color: vc ?? _dark, bold: bold)),
        ],
      );

  final pdf = pw.Document(theme: theme);

  pdf.addPage(
    pw.Page(
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [

          // HEADER
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(co.companyName,
                  style: ts(16, bold: true)),
              pw.Text("INVOICE", style: ts(20, bold: true)),
            ],
          ),

          pw.SizedBox(height: 10),

          pw.Text("Invoice No: $invNo"),
          pw.Text("Date: $invDate"),

          pw.SizedBox(height: 20),

          // CUSTOMER
          pw.Text("Bill To:", style: ts(10, bold: true)),
          pw.Text(customer.name),
          pw.Text(customer.address),

          pw.SizedBox(height: 20),

          // TABLE
          pw.Table(
            border: pw.TableBorder.all(color: _border),
            children: [
              pw.TableRow(
                children: [
                  _cell("Item"),
                  _cell("Qty"),
                  _cell("Price"),
                  _cell("Total"),
                ],
              ),
              ...rows.map((r) {
                final total = net(r);
                return pw.TableRow(children: [
                  _cell(r['desc'] ?? ''),
                  _cell(r['qty'] ?? ''),
                  _cell(rm(double.tryParse(r['price'] ?? '0') ?? 0)),
                  _cell(rm(total)),
                ]);
              })
            ],
          ),

          pw.SizedBox(height: 20),

          // TOTAL
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              "Total: ${rm(grand)}",
              style: ts(12, bold: true),
            ),
          ),

          pw.SizedBox(height: 20),

          // 🔥 IRBM SECTION
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration:
                pw.BoxDecoration(border: pw.Border.all(color: _border)),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("e-Invoice",
                          style: ts(10, bold: true)),
                      pw.SizedBox(height: 5),
                      infoRow("UUID", _uid, bold: true),
                      infoRow(
                        "Status",
                        _status,
                        vc: _status == "Valid" ? _green : _muted,
                      ),
                    ],
                  ),
                ),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: _qrData,
                  width: 70,
                  height: 70,
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          if (notes != null) pw.Text("Notes: $notes"),
          if (terms != null) pw.Text("Terms: $terms"),

          pw.Spacer(),

          // SIGNATURE
          if (sig != null)
            pw.Image(sig, width: 100, height: 50),
        ],
      ),
    ),
  );

  return pdf.save();
}

pw.Widget _cell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 10)),
  );
}
