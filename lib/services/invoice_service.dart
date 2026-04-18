import '../models.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<File> generateInvoicePdf({
  required Settings company,
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

            // 公司名
            pw.Text(company.name ?? "My Company",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),

            pw.SizedBox(height: 10),

            pw.Text("Invoice #: ${transaction.id}"),
            pw.Text("Date: ${transaction.date.toString().split(' ')[0]}"),

            pw.SizedBox(height: 20),

            pw.Text("Description: ${transaction.descEN}"),

            pw.SizedBox(height: 10),

            pw.Text("Amount: RM ${transaction.amountMYR.toStringAsFixed(2)}"),

            pw.Text("SST: RM ${transaction.sstMYR.toStringAsFixed(2)}"),

            pw.Divider(),

            pw.Text(
              "Total: RM ${(transaction.amountMYR + transaction.sstMYR).toStringAsFixed(2)}",
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

  static double tax(double subtotal) {
    return subtotal * 0.06; // SST 6%
  }

  static double total(List<InvoiceItem> items) {
    final sub = subtotal(items);
    return sub + tax(sub);
  }
}
