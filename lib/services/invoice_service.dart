import '../models.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> generateInvoicePdf({
  required AppSettings company,
  required Transaction transaction,
}) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) => pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // Company name
            pw.Text(company.companyName.isNotEmpty ? company.companyName : 'My Company',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),

            pw.SizedBox(height: 10),

            pw.Text('Invoice #: ${transaction.id}'),
            pw.Text('Date: ${transaction.date}'),

            pw.SizedBox(height: 20),

            pw.Text('Description: ${transaction.descEN}'),

            pw.SizedBox(height: 10),

            pw.Text('Amount: RM ${transaction.amountMYR.toStringAsFixed(2)}'),

            pw.Text('SST: RM ${transaction.sstMYR.toStringAsFixed(2)}'),

            pw.Divider(),

            pw.Text(
              'Total: RM ${(transaction.amountMYR + transaction.sstMYR).toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/invoice_${transaction.id}.pdf');

  await file.writeAsBytes(await pdf.save());

  return file;
}

class InvoiceService {
  static double subtotal(List<InvoiceItem> items) {
    return items.fold(0, (sum, i) => sum + i.qty * i.price);
  }

  static double sstAmount(List<InvoiceItem> items, {double rate = 0.06}) {
    return subtotal(items) * rate;
  }


  /// Convenience: tax on a given subtotal at default 6% SST
  static double tax(double subtotal, {double rate = 0.06}) {
    return subtotal * rate;
  }

  static double total(List<InvoiceItem> items, {double sstRate = 0.06}) {
    final sub = subtotal(items);
    return sub + sub * sstRate;
  }

  /// Export line items as CSV string (compatible with Excel / Google Sheets)
  static String toCsv(List<InvoiceItem> items) {
    final buf = StringBuffer();
    buf.writeln('Description,Quantity,Unit Price,Line Total');
    for (final i in items) {
      final qtyStr = i.qty % 1 == 0 ? i.qty.toInt().toString() : i.qty.toStringAsFixed(2);
      buf.writeln('${i.desc},$qtyStr,${i.price.toStringAsFixed(2)},${(i.qty * i.price).toStringAsFixed(2)}');
    }
    buf.writeln('Subtotal,,,${subtotal(items).toStringAsFixed(2)}');
    buf.writeln('SST (6%),,,${sstAmount(items).toStringAsFixed(2)}');
    buf.writeln('Grand Total,,,${total(items).toStringAsFixed(2)}');
    return buf.toString();
  }

  /// Format amount in Malaysian Ringgit with words (for official invoices)
  static String amountInWords(double amount) {
    if (amount < 0) return 'Negative ${amountInWords(-amount)}';
    if (amount >= 1000000) return 'Amount exceeds one million';
    final whole = amount.floor();
    final cents = ((amount - whole) * 100).round();
    final ringgit = _numberToWords(whole);
    if (cents == 0) return 'Ringgit Malaysia $ringgit only';
    return 'Ringgit Malaysia $ringgit and cents $cents only';
  }

  static String _numberToWords(int n) {
    if (n == 0) return 'Zero';
    final ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine'];
    final teens = ['Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    String convert(int num) {
      if (num >= 1000) {
        return '${convert(num ~/ 1000)} Thousand ${convert(num % 1000)}'.trim();
      }
      if (num >= 100) {
        return '${ones[num ~/ 100]} Hundred ${convert(num % 100)}'.trim();
      }
      if (num >= 20) {
        return '${tens[num ~/ 10]} ${ones[num % 10]}'.trim();
      }
      if (num >= 10) return teens[num - 10];
      return ones[num];
    }
    return convert(n);
  }
}