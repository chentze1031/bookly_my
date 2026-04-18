import 'package:flutter/material.dart';
import '../../models.dart';

class InvoiceCustomer extends StatelessWidget {
  final Customer customer;
  final Function(String) onChanged;

  const InvoiceCustomer({
    super.key,
    required this.customer,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: const InputDecoration(labelText: 'Customer Name'),
      onChanged: onChanged,
    );
  }
}
