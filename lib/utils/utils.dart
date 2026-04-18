import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';
import '../services/invoice_service.dart';

Future<Uint8List> generatePdf(List<InvoiceItem> items) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      build: (context) {
        return pw.Column(
          children: [
            pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24)),
            pw.SizedBox(height: 20),

            ...items.map((i) => pw.Text(
                '${i.desc}  ${i.qty} x ${i.price} = ${i.qty * i.price}')),

            pw.SizedBox(height: 20),

            pw.Text('Total: ${InvoiceService.total(items)}'),
          ],
        );
      },
    ),
  );

  return pdf.save();
}
