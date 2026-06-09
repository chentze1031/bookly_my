import 'package:flutter/material.dart';
import '../../models.dart';
import '../../services/invoice_service.dart';

class InvoiceSummary extends StatelessWidget {
  final List<InvoiceItem> items;

  const InvoiceSummary({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final sub = InvoiceService.subtotal(items);
    final tax = InvoiceService.tax(sub);
    final total = InvoiceService.total(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('Subtotal: $sub'),
        Text('SST: $tax'),
        Text('Total: $total', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
