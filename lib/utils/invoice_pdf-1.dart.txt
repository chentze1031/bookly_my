// ─── invoice_pdf.dart ─────────────────────────────────────────────────────────
// Malaysia Tax Invoice — clean black/white layout
// v2: adds bankAcctName, shipToName, shipToAddr, paymentMethod,
//     paymentTerms, latePenalty, amount-in-words, SST breakdown
//     removes co.coTin (not in AppSettings)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _black  = PdfColors.black;
const _grey   = PdfColor.fromInt(0xFF555555);
const _light  = PdfColor.fromInt(0xFF888888);
const _rule   = PdfColor.fromInt(0xFFBBBBBB);
const _white  = PdfColors.white;
const _rowAlt = PdfColor.fromInt(0xFFF7F7F7);

// ── SST maps ──────────────────────────────────────────────────────────────────
const _sstRate = {
  'none': 0.0, 'sst5': 0.05, 'sst10': 0.10,
  'service6': 0.06, 'service8': 0.08,
};
const _sstLabel = {
  'none': '—', 'sst5': 'Sales 5%', 'sst10': 'Sales 10%',
  'service6': 'Svc 6%', 'service8': 'Svc 8%',
};
const _isSalesTax = {'sst5', 'sst10'};

// ── Amount in words ───────────────────────────────────────────────────────────
String _amountInWords(double amount) {
  final total = amount.truncate();
  final cents = ((amount - total) * 100).round();
  final words = _toWords(total);
  final centsStr = cents > 0 ? ' and Cents ${_toWords(cents)} Only' : ' Only';
  return 'Malaysian Ringgit $words$centsStr';
}

String _toWords(int n) {
  if (n == 0) return 'Zero';
  const ones = ['','One','Two','Three','Four','Five','Six','Seven','Eight',
    'Nine','Ten','Eleven','Twelve','Thirteen','Fourteen','Fifteen','Sixteen',
    'Seventeen','Eighteen','Nineteen'];
  const tens = ['','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy',
    'Eighty','Ninety'];
  if (n < 20)   return ones[n];
  if (n < 100)  return '${tens[n ~/ 10]}${n % 10 > 0 ? ' ${ones[n % 10]}' : ''}';
  if (n < 1000) return '${ones[n ~/ 100]} Hundred${n % 100 > 0 ? ' ${_toWords(n % 100)}' : ''}';
  if (n < 1000000) return '${_toWords(n ~/ 1000)} Thousand${n % 1000 > 0 ? ' ${_toWords(n % 1000)}' : ''}';
  return '${_toWords(n ~/ 1000000)} Million${n % 1000000 > 0 ? ' ${_toWords(n % 1000000)}' : ''}';
}

// ── Main function ─────────────────────────────────────────────────────────────
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
  String? bankAcctName,
  String? shipToName,
  String? shipToAddr,
  String? paymentMethod,
  String? paymentTerms,
  String? latePenalty,
}) async {

  // ── CJK font (fix: fontFallback on every TextStyle) ───────────────────────
  pw.Font? cjk;
  pw.Font? cjkBold;
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    cjk = pw.Font.ttf(fd);
  } catch (_) {}
  try {
    final fd = await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf');
    cjkBold = pw.Font.ttf(fd);
  } catch (_) { cjkBold = cjk; }

  final List<pw.Font> fb = cjk != null ? [cjk] : [];

  final pw.ThemeData theme = cjk != null
      ? pw.ThemeData.withFont(base: cjk, bold: cjkBold ?? cjk)
      : pw.ThemeData();

  // ── Style helper ──────────────────────────────────────────────────────────
  pw.TextStyle ts(double sz, {PdfColor? c, bool bold = false}) => pw.TextStyle(
      fontSize: sz,
      color: c ?? _black,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontFallback: fb);

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
  double netOf(Map<String, String> r) {
    final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
    return qty * price * (1 - disc / 100);
  }
  double sstOf(Map<String, String> r) =>
      netOf(r) * (_sstRate[r['sst'] ?? 'none'] ?? 0);

  final subtotal = rows.fold<double>(0, (s, r) => s + netOf(r));
  final totalSST = rows.fold<double>(0, (s, r) => s + sstOf(r));
  final grand    = subtotal + totalSST;
  final isTax    = co.sstRegNo.isNotEmpty;
  final hasSst   = totalSST > 0;

  // SST buckets
  final Map<String, _TaxBucket> buckets = {};
  for (final r in rows) {
    final key = r['sst'] ?? 'none';
    if (key == 'none') continue;
    buckets[key] = _TaxBucket(
      label:   _sstLabel[key] ?? key,
      isSales: _isSalesTax.contains(key),
      netAmt:  (buckets[key]?.netAmt ?? 0) + netOf(r),
      sstAmt:  (buckets[key]?.sstAmt ?? 0) + sstOf(r),
    );
  }

  String rm(double v) => 'RM ${v.toStringAsFixed(2)}';

  // ── Widget helpers ────────────────────────────────────────────────────────
  pw.Widget rule({double thick = 0.5, PdfColor? color}) =>
      pw.Divider(thickness: thick, color: color ?? _rule, height: 1);
  pw.Widget gap(double h) => pw.SizedBox(height: h);

  // ── Build ─────────────────────────────────────────────────────────────────
  final pdf = pw.Document(theme: theme);

  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(52, 48, 52, 40),
    footer: (ctx) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by Bookly MY  ·  $invDate', style: ts(7, c: _light)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: ts(7, c: _light)),
        ],
      ),
    ),
    build: (ctx) => [

      // ══ HEADER ══════════════════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, height: 44, fit: pw.BoxFit.contain),
                  gap(6),
                ],
                pw.Text(co.companyName, style: ts(11, bold: true)),
                if (co.coReg.isNotEmpty)
                  pw.Text('SSM Reg No: ${co.coReg}',    style: ts(8, c: _grey)),
                if (co.sstRegNo.isNotEmpty)
                  pw.Text('SST Reg No: ${co.sstRegNo}', style: ts(8, c: _grey)),
                if (co.coAddr.isNotEmpty)
                  pw.Text(co.coAddr,                    style: ts(8, c: _grey)),
                if (co.coPhone.isNotEmpty)
                  pw.Text('Tel: ${co.coPhone}',         style: ts(8, c: _grey)),
                if (co.coEmail.isNotEmpty)
                  pw.Text(co.coEmail,                   style: ts(8, c: _grey)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(isTax ? 'TAX INVOICE' : 'INVOICE', style: ts(20, bold: true)),
              gap(10),
              _metaRow('Invoice No', invNo,   ts(8, c: _grey), ts(8, bold: true)),
              _metaRow('Date',       invDate, ts(8, c: _grey), ts(8)),
              if (dueDate != null && dueDate.isNotEmpty)
                _metaRow('Due Date', dueDate, ts(8, c: _grey), ts(8, bold: true)),
              if (paymentTerms != null && paymentTerms.isNotEmpty)
                _metaRow('Terms',    paymentTerms, ts(8, c: _grey), ts(8)),
            ],
          ),
        ],
      ),

      gap(20),
      rule(thick: 1.0, color: _black),
      gap(14),

      // ══ BILL TO + SHIP TO ════════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('BILL TO', style: ts(7, c: _light, bold: true)),
                gap(4),
                pw.Text(customer.name, style: ts(10, bold: true)),
                if (customer.regNo.isNotEmpty)
                  pw.Text('SSM: ${customer.regNo}',    style: ts(8, c: _grey)),
                if (customer.sstRegNo.isNotEmpty)
                  pw.Text('SST: ${customer.sstRegNo}', style: ts(8, c: _grey)),
                if (customer.address.isNotEmpty)
                  pw.Text(customer.address,            style: ts(8, c: _grey)),
                if (customer.phone.isNotEmpty)
                  pw.Text(customer.phone,              style: ts(8, c: _grey)),
                if (customer.email.isNotEmpty)
                  pw.Text(customer.email,              style: ts(8, c: _grey)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('SHIP TO', style: ts(7, c: _light, bold: true)),
                gap(4),
                if (shipToName != null && shipToName.isNotEmpty) ...[
                  pw.Text(shipToName, style: ts(10, bold: true),
                      textAlign: pw.TextAlign.right),
                  if (shipToAddr != null && shipToAddr.isNotEmpty)
                    pw.Text(shipToAddr, style: ts(8, c: _grey),
                        textAlign: pw.TextAlign.right),
                ] else ...[
                  pw.Text(customer.name, style: ts(10, bold: true),
                      textAlign: pw.TextAlign.right),
                  pw.Text('Same as billing address', style: ts(8, c: _light),
                      textAlign: pw.TextAlign.right),
                ],
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
          pw.SizedBox(width: 20,
              child: pw.Text('NO',          style: ts(7.5, c: _grey, bold: true))),
          pw.Expanded(flex: 5,
              child: pw.Text('DESCRIPTION', style: ts(7.5, c: _grey, bold: true))),
          pw.SizedBox(width: 36,
              child: pw.Text('QTY',         style: ts(7.5, c: _grey, bold: true),
                  textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 68,
              child: pw.Text('UNIT PRICE',  style: ts(7.5, c: _grey, bold: true),
                  textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 36,
              child: pw.Text('DISC%',       style: ts(7.5, c: _grey, bold: true),
                  textAlign: pw.TextAlign.right)),
          if (hasSst)
            pw.SizedBox(width: 52,
                child: pw.Text('SST',       style: ts(7.5, c: _grey, bold: true),
                    textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 68,
              child: pw.Text('AMOUNT',      style: ts(7.5, c: _grey, bold: true),
                  textAlign: pw.TextAlign.right)),
        ]),
      ),
      rule(thick: 1.0, color: _black),

      // ══ TABLE ROWS ════════════════════════════════════════════════════════
      ...rows.asMap().entries.map((e) {
        final i     = e.key;
        final r     = e.value;
        final n     = netOf(r);
        final s     = sstOf(r);
        final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
        final price = double.tryParse(r['price'] ?? '0') ?? 0;
        final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
        final sstKey = r['sst'] ?? 'none';
        return pw.Container(
          color: i.isOdd ? _rowAlt : _white,
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: 20,
                    child: pw.Text('${i + 1}', style: ts(9, c: _grey))),
                pw.Expanded(flex: 5, child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(r['desc'] ?? '', style: ts(9, bold: true)),
                    if ((r['note'] ?? '').isNotEmpty)
                      pw.Text(r['note']!, style: ts(7.5, c: _grey)),
                  ],
                )),
                pw.SizedBox(width: 36,
                    child: pw.Text(
                      qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2),
                      style: ts(9), textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 68,
                    child: pw.Text(rm(price), style: ts(9),
                        textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 36,
                    child: pw.Text(
                      disc > 0
                          ? '${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}%'
                          : '—',
                      style: ts(9, c: disc > 0 ? _grey : _light),
                      textAlign: pw.TextAlign.right)),
                if (hasSst)
                  pw.SizedBox(width: 52,
                      child: pw.Text(
                        sstKey != 'none' ? _sstLabel[sstKey]! : 'Exempt',
                        style: ts(8, c: _grey),
                        textAlign: pw.TextAlign.right)),
                pw.SizedBox(width: 68,
                    child: pw.Text(rm(n + s), style: ts(9, bold: true),
                        textAlign: pw.TextAlign.right)),
              ],
            ),
          ),
        );
      }),

      rule(thick: 1.0, color: _black),
      gap(10),

      // ══ SST BREAKDOWN + TOTALS ════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // SST breakdown
          pw.Expanded(
            child: buckets.isEmpty
                ? pw.SizedBox()
                : pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SST BREAKDOWN',
                          style: ts(7, c: _light, bold: true)),
                      gap(5),
                      pw.Row(children: [
                        pw.Expanded(child: pw.SizedBox()),
                        pw.SizedBox(width: 70,
                            child: pw.Text('Taxable Amt',
                                style: ts(7.5, c: _light),
                                textAlign: pw.TextAlign.right)),
                        pw.SizedBox(width: 60,
                            child: pw.Text('Tax Amt',
                                style: ts(7.5, c: _light),
                                textAlign: pw.TextAlign.right)),
                      ]),
                      gap(3),
                      rule(),
                      gap(3),
                      ...buckets.entries.map((e) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 3),
                        child: pw.Row(children: [
                          pw.Expanded(child: pw.Text(
                            '${e.value.isSales ? "Sales Tax" : "Service Tax"} ${e.value.label}',
                            style: ts(8))),
                          pw.SizedBox(width: 70,
                              child: pw.Text(rm(e.value.netAmt), style: ts(8),
                                  textAlign: pw.TextAlign.right)),
                          pw.SizedBox(width: 60,
                              child: pw.Text(rm(e.value.sstAmt),
                                  style: ts(8, bold: true),
                                  textAlign: pw.TextAlign.right)),
                        ]),
                      )),
                    ],
                  ),
          ),
          pw.SizedBox(width: 20),
          // Totals
          pw.SizedBox(
            width: 220,
            child: pw.Column(children: [
              _totalLine('Subtotal (excl. SST)', rm(subtotal),
                  ts(9, c: _grey), ts(9)),
              if (hasSst) ...[
                gap(3),
                ...buckets.entries.map((e) => _totalLine(
                  '${e.value.isSales ? "Sales" : "Service"} Tax ${e.value.label}',
                  rm(e.value.sstAmt),
                  ts(9, c: _grey), ts(9),
                )),
                gap(3),
                _totalLine('Total SST', rm(totalSST),
                    ts(9, c: _grey), ts(9, bold: true)),
              ],
              gap(6),
              rule(thick: 1.0, color: _black),
              gap(6),
              _totalLine('TOTAL DUE', rm(grand),
                  ts(11, bold: true), ts(11, bold: true)),
            ]),
          ),
        ],
      ),

      gap(10),

      // ══ AMOUNT IN WORDS ══════════════════════════════════════════════════
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule),
          borderRadius: pw.BorderRadius.circular(3),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Amount in Words:  ', style: ts(7.5, c: _light, bold: true)),
            pw.Expanded(
              child: pw.Text(_amountInWords(grand),
                  style: ts(7.5, c: _grey, bold: true)),
            ),
          ],
        ),
      ),

      gap(16),
      rule(),
      gap(12),

      // ══ PAYMENT INFO + NOTES ══════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Payment
          if (bankName != null && bankName.isNotEmpty)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PAYMENT INFORMATION',
                      style: ts(7, c: _light, bold: true)),
                  gap(5),
                  if (paymentMethod != null && paymentMethod.isNotEmpty)
                    _infoLine('Method',       paymentMethod, ts(8, c: _grey), ts(8)),
                  if (paymentTerms != null && paymentTerms.isNotEmpty)
                    _infoLine('Terms',        paymentTerms,  ts(8, c: _grey), ts(8)),
                  if (dueDate != null && dueDate.isNotEmpty)
                    _infoLine('Due Date',     dueDate,       ts(8, c: _grey), ts(8, bold: true)),
                  if (latePenalty != null && latePenalty.isNotEmpty)
                    _infoLine('Late Fee',     latePenalty,   ts(8, c: _grey), ts(8)),
                  gap(6),
                  pw.Text('BANK TRANSFER', style: ts(7, c: _light, bold: true)),
                  gap(4),
                  _infoLine('Bank',         bankName,      ts(8, c: _grey), ts(8, bold: true)),
                  if (bankAcctName != null && bankAcctName.isNotEmpty)
                    _infoLine('Account Name', bankAcctName, ts(8, c: _grey), ts(8)),
                  if (bankAcct != null && bankAcct.isNotEmpty)
                    _infoLine('Account No.', bankAcct,     ts(8, c: _grey), ts(8, bold: true)),
                  _infoLine('Reference',    invNo,         ts(8, c: _grey), ts(8)),
                ],
              ),
            ),
          // Notes + Terms
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (notes != null && notes.isNotEmpty) ...[
                  pw.Text('NOTES', style: ts(7, c: _light, bold: true)),
                  gap(3),
                  pw.Text(notes, style: ts(8, c: _grey)),
                  gap(8),
                ],
                if (terms != null && terms.isNotEmpty) ...[
                  pw.Text('TERMS & CONDITIONS',
                      style: ts(7, c: _light, bold: true)),
                  gap(3),
                  pw.Text(terms, style: ts(7.5, c: _grey)),
                  gap(6),
                ],
                pw.Text('E. & O. E.  —  Errors and Omissions Excepted.',
                    style: ts(7, c: _light)),
              ],
            ),
          ),
        ],
      ),

      gap(18),
      rule(thick: 1.0, color: _black),
      gap(10),

      // ══ FOOTER ══════════════════════════════════════════════════════════
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('DECLARATION', style: ts(7, c: _light, bold: true)),
                gap(3),
                pw.Text(
                  'This is a computer-generated ${isTax ? "Tax Invoice" : "Invoice"} '
                  'issued in compliance with the Malaysian SST Act 2018. '
                  'No physical signature required unless stated otherwise.',
                  style: ts(7.5, c: _grey),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 20),
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
                    border: pw.Border(
                        top: pw.BorderSide(color: _black, width: 0.8))),
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
  ));

  return pdf.save();
}

// ── Helpers ───────────────────────────────────────────────────────────────────
pw.Widget _metaRow(String label, String value,
    pw.TextStyle ls, pw.TextStyle vs) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(children: [
        pw.SizedBox(width: 72, child: pw.Text(label, style: ls)),
        pw.Text(value, style: vs),
      ]),
    );

pw.Widget _totalLine(String label, String value,
    pw.TextStyle ls, pw.TextStyle vs) =>
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [pw.Text(label, style: ls), pw.Text(value, style: vs)],
    );

pw.Widget _infoLine(String label, String value,
    pw.TextStyle ls, pw.TextStyle vs) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: ls)),
          pw.Expanded(child: pw.Text(value, style: vs)),
        ],
      ),
    );

class _TaxBucket {
  final String label;
  final bool   isSales;
  final double netAmt, sstAmt;
  _TaxBucket({required this.label, required this.isSales,
      required this.netAmt, required this.sstAmt});
}
