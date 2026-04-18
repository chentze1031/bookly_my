import 'package:flutter/material.dart';
import '../../models.dart';

class InvoiceItems extends StatelessWidget {
  final List<InvoiceItem> items;
  final VoidCallback onAdd;

  const InvoiceItems({
    super.key,
    required this.items,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...items.map((item) => ListTile(
              title: Text(item.desc),
              subtitle: Text('Qty: ${item.qty}  Price: ${item.price}'),
            )),
        ElevatedButton(
          onPressed: onAdd,
          child: const Text('Add Item'),
        )
      ],
    );
  }
}
