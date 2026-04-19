// ─── invoice_pdf.dart ─────────────────────────────────────────────────────────
// Clean minimal invoice — white background, black text, hairline rules only.
// Layout: company top-left | invoice title top-right | bill-to | table | totals
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

// ── Palette: black / grey only ────────────────────────────────────────────────
const _black  = PdfColors.black;
const _grey   = PdfColor.fromInt(0xFF555555);
const _light  = PdfColor.fromInt(0xFF888888);
const _rule   = PdfColor.fromInt(0xFFBBBBBB);
const _white  = PdfColors.white;
const _rowAlt = PdfColor.fromInt(0xFFF7F7F7);

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
  const sstMap = {
    'none': 0.0, 'sst5': 0.05, 'sst10': 0.10,
    'service6': 0.06, 'service8': 0.08,
  };

  double netOf(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }
  double sstOf(Map<String, String> r) => netOf(r) * (sstMap[r['sst'] ?? 'none'] ?? 0);

  final subtotal = rows.fold<double>(0, (s, r) => s + netOf(r));
  final totalSST = rows.fold<double>(0, (s, r) => s + sstOf(r));
  final grand    = subtotal + totalSST;
  final isTax    = co.sstRegNo.isNotEmpty;
  final hasSst   = totalSST > 0;

  String rm(double v) => 'RM ${v.toStringAsFixed(2)}';

  // ── Style helpers ─────────────────────────────────────────────────────────
  pw.TextStyle ts(double sz, {PdfColor? c, bool bold = false}) => pw.TextStyle(
      fontSize: sz,
      color: c ?? _black,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

  pw.Widget rule({double thick = 0.5, PdfColor? color}) =>
      pw.Divider(thickness: thick, color: color ?? _rule, height: 1);

  pw.Widget gap(double h) => pw.SizedBox(height: h);

  // ── Build ─────────────────────────────────────────────────────────────────
  final pdf = pw.Document(theme: theme);

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(52, 48, 52, 40),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // ══ HEADER: Logo+Company left | Title+No right ══════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left — company
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo, height: 44, fit: pw.BoxFit.contain),
                    gap(6),
                  ],
                  pw.Text(co.companyName, style: ts(11, bold: true)),
                  if (co.coReg.isNotEmpty)    pw.Text('Reg No: ${co.coReg}',       style: ts(8, c: _grey)),
                  if (co.sstRegNo.isNotEmpty) pw.Text('SST No: ${co.sstRegNo}',    style: ts(8, c: _grey)),
                  if (co.coTin.isNotEmpty)    pw.Text('TIN: ${co.coTin}',          style: ts(8, c: _grey)),
                  if (co.coAddr.isNotEmpty)   pw.Text(co.coAddr,                   style: ts(8, c: _grey)),
                  if (co.coPhone.isNotEmpty)  pw.Text(co.coPhone,                  style: ts(8, c: _grey)),
                  if (co.coEmail.isNotEmpty)  pw.Text(co.coEmail,                  style: ts(8, c: _grey)),
                ],
              ),
            ),
            // Right — invoice title block
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(isTax ? 'TAX INVOICE' : 'INVOICE',
                    style: ts(20, bold: true)),
                gap(10),
                _metaRow('Invoice No',   invNo,   ts(8, c: _grey), ts(8, bold: true)),
                _metaRow('Date',         invDate, ts(8, c: _grey), ts(8)),
                if (dueDate != null && dueDate.isNotEmpty)
                  _metaRow('Due Date', dueDate, ts(8, c: _grey), ts(8)),
              ],
            ),
          ],
        ),

        gap(20),
        rule(thick: 1.0, color: _black),
        gap(14),

        // ══ BILL TO ══════════════════════════════════════════════════════════
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Bill to
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BILL TO', style: ts(7, c: _light, bold: true)),
                  gap(4),
                  pw.Text(customer.name, style: ts(10, bold: true)),
                  if (customer.regNo.isNotEmpty)    pw.Text('Reg: ${customer.regNo}',       style: ts(8, c: _grey)),
                  if (customer.sstRegNo.isNotEmpty) pw.Text('SST: ${customer.sstRegNo}',    style: ts(8, c: _grey)),
                  if (customer.address.isNotEmpty)  pw.Text(customer.address,               style: ts(8, c: _grey)),
                  if (customer.phone.isNotEmpty)    pw.Text(customer.phone,                 style: ts(8, c: _grey)),
                  if (customer.email.isNotEmpty)    pw.Text(customer.email,                 style: ts(8, c: _grey)),
                ],
              ),
            ),
            // Payment to (bank)
            if (bankName != null && bankName.isNotEmpty)
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PAYMENT TO', style: ts(7, c: _light, bold: true)),
                    gap(4),
                    pw.Text(bankName,           style: ts(9, bold: true)),
                    if (bankAcct != null && bankAcct.isNotEmpty)
                      pw.Text(bankAcct,         style: ts(9)),
                    pw.Text(co.companyName,     style: ts(8, c: _grey)),
                  ],
                ),
              ),
          ],
        ),

        gap(18),
        rule(thick: 1.0, color: _black),

        // ══ TABLE HEADER ══════════════════════════════════════════════════════
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.Row(children: [
            pw.Expanded(flex: 5, child: pw.Text('DESCRIPTION', style: ts(7.5, c: _grey, bold: true))),
            pw.SizedBox(width: 44, child: pw.Text('QTY',        style: ts(7.5, c: _grey, bold: true), textAlign: pw.TextAlign.center)),
            pw.SizedBox(width: 72, child: pw.Text('UNIT PRICE', style: ts(7.5, c: _grey, bold: true), textAlign: pw.TextAlign.right)),
            if (hasSst)
              pw.SizedBox(width: 52, child: pw.Text('SST',      style: ts(7.5, c: _grey, bold: true), textAlign: pw.TextAlign.right)),
            pw.SizedBox(width: 72, child: pw.Text('AMOUNT',     style: ts(7.5, c: _grey, bold: true), textAlign: pw.TextAlign.right)),
          ]),
        ),
        rule(),

        // ══ TABLE ROWS ════════════════════════════════════════════════════════
        ...rows.asMap().entries.map((e) {
          final i    = e.key;
          final r    = e.value;
          final n    = netOf(r);
          final s    = sstOf(r);
          final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
          final price = double.tryParse(r['price'] ?? '0') ?? 0;
          return pw.Container(
            color: i.isOdd ? _rowAlt : _white,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(flex: 5, child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(r['desc'] ?? '', style: ts(9, bold: true)),
                      if ((r['note'] ?? '').isNotEmpty)
                        pw.Text(r['note'] ?? '', style: ts(7.5, c: _grey)),
                      if (disc > 0)
                        pw.Text('${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}% discount applied',
                            style: ts(7.5, c: _light)),
                    ],
                  )),
                  pw.SizedBox(width: 44,
                      child: pw.Text(r['qty'] ?? '1', style: ts(9), textAlign: pw.TextAlign.center)),
                  pw.SizedBox(width: 72,
                      child: pw.Text(rm(price), style: ts(9), textAlign: pw.TextAlign.right)),
                  if (hasSst)
                    pw.SizedBox(width: 52,
                        child: pw.Text(s > 0 ? rm(s) : '—', style: ts(9, c: _grey),
                            textAlign: pw.TextAlign.right)),
                  pw.SizedBox(width: 72,
                      child: pw.Text(rm(n + s), style: ts(9, bold: true),
                          textAlign: pw.TextAlign.right)),
                ],
              ),
            ),
          );
        }),

        rule(),
        gap(12),

        // ══ TOTALS (right-aligned) ════════════════════════════════════════════
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(children: [
              _totalLine('Subtotal', rm(subtotal), ts(9, c: _grey), ts(9)),
              if (hasSst) ...[
                gap(3),
                _totalLine('SST',      rm(totalSST), ts(9, c: _grey), ts(9)),
              ],
              gap(6),
              rule(thick: 1.0, color: _black),
              gap(6),
              _totalLine('TOTAL DUE', rm(grand), ts(11, bold: true), ts(11, bold: true)),
            ]),
          ),
        ),

        pw.Spacer(),

        // ══ FOOTER ════════════════════════════════════════════════════════════
        rule(),
        gap(10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Left: notes + terms + generated
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (notes != null && notes.isNotEmpty) ...[
                    pw.Text('Notes', style: ts(7, c: _light, bold: true)),
                    gap(2),
                    pw.Text(notes, style: ts(8, c: _grey)),
                    gap(6),
                  ],
                  if (terms != null && terms.isNotEmpty) ...[
                    pw.Text('Terms & Conditions', style: ts(7, c: _light, bold: true)),
                    gap(2),
                    pw.Text(terms, style: ts(7.5, c: _grey)),
                    gap(6),
                  ],
                  pw.Text(
                    'Generated by Bookly MY · $invDate',
                    style: ts(7, c: _light),
                  ),
                ],
              ),
            ),
            gap(16),
            // Right: signature
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (sig != null)
                  pw.Image(sig, width: 110, height: 44, fit: pw.BoxFit.contain)
                else
                  pw.SizedBox(width: 110, height: 44),
                pw.Container(
                  width: 130,
                  decoration: const pw.BoxDecoration(
                      border: pw.Border(top: pw.BorderSide(color: _black, width: 0.8))),
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Column(children: [
                    pw.Text('Authorised Signature', style: ts(7, c: _grey),
                        textAlign: pw.TextAlign.center),
                    pw.Text(co.companyName, style: ts(7.5, bold: true),
                        textAlign: pw.TextAlign.center),
                  ]),
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

// ── Helper widgets ────────────────────────────────────────────────────────────
pw.Widget _metaRow(String label, String value, pw.TextStyle ls, pw.TextStyle vs) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(children: [
        pw.SizedBox(width: 70, child: pw.Text(label, style: ls)),
        pw.Text(value, style: vs),
      ]),
    );

pw.Widget _totalLine(String label, String value, pw.TextStyle ls, pw.TextStyle vs) =>
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: ls),
        pw.Text(value, style: vs),
      ],
    );
