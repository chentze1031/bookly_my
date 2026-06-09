import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
// ACCOUNTING MODELS
// ════════════════════════════════════════════════════════════════════════════

// ── Invoice Status ────────────────────────────────────────────────────────────
enum InvoiceStatus { draft, sent, partial, paid, overdue, void_ }

extension InvoiceStatusExt on InvoiceStatus {
  String get label => switch (this) {
    InvoiceStatus.draft   => 'Draft',
    InvoiceStatus.sent    => 'Sent',
    InvoiceStatus.partial => 'Partial',
    InvoiceStatus.paid    => 'Paid',
    InvoiceStatus.overdue => 'Overdue',
    InvoiceStatus.void_   => 'Void',
  };
  Color get color => switch (this) {
    InvoiceStatus.draft   => const Color(0xFF888888),
    InvoiceStatus.sent    => const Color(0xFF2196F3),
    InvoiceStatus.partial => const Color(0xFFFF9800),
    InvoiceStatus.paid    => const Color(0xFF4CAF50),
    InvoiceStatus.overdue => const Color(0xFFF44336),
    InvoiceStatus.void_   => const Color(0xFF9E9E9E),
  };
  String get icon => switch (this) {
    InvoiceStatus.draft   => '📝',
    InvoiceStatus.sent    => '📤',
    InvoiceStatus.partial => '⏳',
    InvoiceStatus.paid    => '✅',
    InvoiceStatus.overdue => '🔴',
    InvoiceStatus.void_   => '🚫',
  };
  static InvoiceStatus fromString(String s) => InvoiceStatus.values.firstWhere(
    (e) => e.name == s, orElse: () => InvoiceStatus.draft);
}

// ── AR Invoice (Accounts Receivable) ─────────────────────────────────────────
class ArInvoice {
  final int    id;
  final String invNo;
  final String customerId;
  final String customerName;
  final String issueDate;   // yyyy-MM-dd
  final String dueDate;     // yyyy-MM-dd
  final double subtotal;
  final double sstAmount;
  final double total;
  final double amountPaid;
  final InvoiceStatus status;
  final String? notes;
  final List<ArInvoiceItem> items;

  const ArInvoice({
    required this.id,
    required this.invNo,
    required this.customerId,
    required this.customerName,
    required this.issueDate,
    required this.dueDate,
    required this.subtotal,
    required this.sstAmount,
    required this.total,
    required this.amountPaid,
    required this.status,
    this.notes,
    required this.items,
  });

  double get balance       => total - amountPaid;
  bool   get isOverdue     => status != InvoiceStatus.paid &&
                              DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true;
  int    get daysOverdue   {
    if (!isOverdue) return 0;
    return DateTime.now().difference(DateTime.parse(dueDate)).inDays;
  }
  String get agingBucket   {
    if (!isOverdue) return 'Current';
    final d = daysOverdue;
    if (d <= 30)  return '1-30 days';
    if (d <= 60)  return '31-60 days';
    if (d <= 90)  return '61-90 days';
    return '90+ days';
  }

  ArInvoice copyWith({
    InvoiceStatus? status,
    double? amountPaid,
    String? notes,
  }) => ArInvoice(
    id: id, invNo: invNo, customerId: customerId, customerName: customerName,
    issueDate: issueDate, dueDate: dueDate, subtotal: subtotal,
    sstAmount: sstAmount, total: total,
    amountPaid: amountPaid ?? this.amountPaid,
    status: status ?? this.status,
    notes: notes ?? this.notes,
    items: items,
  );

  Map<String, dynamic> toMap() => {
    'id':            id,
    'inv_no':        invNo,
    'customer_id':   customerId,
    'customer_name': customerName,
    'issue_date':    issueDate,
    'due_date':      dueDate,
    'subtotal':      subtotal,
    'sst_amount':    sstAmount,
    'total':         total,
    'amount_paid':   amountPaid,
    'status':        status.name,
    'notes':         notes,
    'items':         items.map((i) => i.toMap()).toList(),
  };

  factory ArInvoice.fromMap(Map<String, dynamic> m) => ArInvoice(
    id:           m['id'] as int,
    invNo:        m['inv_no'] as String,
    customerId:   m['customer_id'] as String,
    customerName: m['customer_name'] as String,
    issueDate:    m['issue_date'] as String,
    dueDate:      m['due_date'] as String,
    subtotal:     (m['subtotal'] as num).toDouble(),
    sstAmount:    (m['sst_amount'] as num).toDouble(),
    total:        (m['total'] as num).toDouble(),
    amountPaid:   (m['amount_paid'] as num).toDouble(),
    status:       InvoiceStatusExt.fromString(m['status'] as String),
    notes:        m['notes'] as String?,
    items:        (m['items'] as List? ?? []).map((i) => ArInvoiceItem.fromMap(i)).toList(),
  );
}

class ArInvoiceItem {
  final String description;
  final double qty;
  final double unitPrice;
  final double amount;

  const ArInvoiceItem({
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.amount,
  });

  Map<String, dynamic> toMap() => {
    'description': description,
    'qty':         qty,
    'unit_price':  unitPrice,
    'amount':      amount,
  };

  factory ArInvoiceItem.fromMap(Map<String, dynamic> m) => ArInvoiceItem(
    description: m['description'] as String,
    qty:         (m['qty'] as num).toDouble(),
    unitPrice:   (m['unit_price'] as num).toDouble(),
    amount:      (m['amount'] as num).toDouble(),
  );
}

// ── AP Bill (Accounts Payable) ────────────────────────────────────────────────
class ApBill {
  final int    id;
  final String billNo;
  final String supplierId;
  final String supplierName;
  final String issueDate;
  final String dueDate;
  final double subtotal;
  final double sstAmount;
  final double total;
  final double amountPaid;
  final InvoiceStatus status;
  final String? notes;
  final String? category; // expense category

  const ApBill({
    required this.id,
    required this.billNo,
    required this.supplierId,
    required this.supplierName,
    required this.issueDate,
    required this.dueDate,
    required this.subtotal,
    required this.sstAmount,
    required this.total,
    required this.amountPaid,
    required this.status,
    this.notes,
    this.category,
  });

  double get balance     => total - amountPaid;
  bool   get isOverdue   => status != InvoiceStatus.paid &&
                            DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true;
  int    get daysOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(DateTime.parse(dueDate)).inDays;
  }
  String get agingBucket {
    if (!isOverdue) return 'Current';
    final d = daysOverdue;
    if (d <= 30)  return '1-30 days';
    if (d <= 60)  return '31-60 days';
    if (d <= 90)  return '61-90 days';
    return '90+ days';
  }

  ApBill copyWith({InvoiceStatus? status, double? amountPaid, String? notes}) =>
    ApBill(
      id: id, billNo: billNo, supplierId: supplierId, supplierName: supplierName,
      issueDate: issueDate, dueDate: dueDate, subtotal: subtotal,
      sstAmount: sstAmount, total: total,
      amountPaid: amountPaid ?? this.amountPaid,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      category: category,
    );

  Map<String, dynamic> toMap() => {
    'id':            id,
    'bill_no':       billNo,
    'supplier_id':   supplierId,
    'supplier_name': supplierName,
    'issue_date':    issueDate,
    'due_date':      dueDate,
    'subtotal':      subtotal,
    'sst_amount':    sstAmount,
    'total':         total,
    'amount_paid':   amountPaid,
    'status':        status.name,
    'notes':         notes,
    'category':      category,
  };

  factory ApBill.fromMap(Map<String, dynamic> m) => ApBill(
    id:           m['id'] as int,
    billNo:       m['bill_no'] as String,
    supplierId:   m['supplier_id'] as String,
    supplierName: m['supplier_name'] as String,
    issueDate:    m['issue_date'] as String,
    dueDate:      m['due_date'] as String,
    subtotal:     (m['subtotal'] as num).toDouble(),
    sstAmount:    (m['sst_amount'] as num).toDouble(),
    total:        (m['total'] as num).toDouble(),
    amountPaid:   (m['amount_paid'] as num).toDouble(),
    status:       InvoiceStatusExt.fromString(m['status'] as String),
    notes:        m['notes'] as String?,
    category:     m['category'] as String?,
  );
}

// ── Supplier ──────────────────────────────────────────────────────────────────
class Supplier {
  final int    id;
  final String name;
  final String regNo;
  final String sstRegNo;
  final String address;
  final String phone;
  final String email;
  final String? bankName;
  final String? bankAcct;

  const Supplier({
    required this.id,
    required this.name,
    this.regNo    = '',
    this.sstRegNo = '',
    this.address  = '',
    this.phone    = '',
    this.email    = '',
    this.bankName,
    this.bankAcct,
  });

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'reg_no': regNo, 'sst_reg_no': sstRegNo,
    'address': address, 'phone': phone, 'email': email,
    'bank_name': bankName, 'bank_acct': bankAcct,
  };

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
    id:       m['id'] as int,
    name:     m['name'] as String,
    regNo:    m['reg_no'] ?? '',
    sstRegNo: m['sst_reg_no'] ?? '',
    address:  m['address'] ?? '',
    phone:    m['phone'] ?? '',
    email:    m['email'] ?? '',
    bankName: m['bank_name'] as String?,
    bankAcct: m['bank_acct'] as String?,
  );

  Supplier copyWith({
    String? name, String? regNo, String? sstRegNo,
    String? address, String? phone, String? email,
    String? bankName, String? bankAcct,
  }) => Supplier(
    id: id,
    name:     name     ?? this.name,
    regNo:    regNo    ?? this.regNo,
    sstRegNo: sstRegNo ?? this.sstRegNo,
    address:  address  ?? this.address,
    phone:    phone    ?? this.phone,
    email:    email    ?? this.email,
    bankName: bankName ?? this.bankName,
    bankAcct: bankAcct ?? this.bankAcct,
  );
}

// ── GL Account Entry (for Trial Balance / General Ledger) ─────────────────────
class GlAccountSummary {
  final String code;
  final String name;
  final String type;   // Asset | Liability | Equity | Revenue | Expense
  final double debit;
  final double credit;

  const GlAccountSummary({
    required this.code,
    required this.name,
    required this.type,
    required this.debit,
    required this.credit,
  });

  double get balance => debit - credit;
  double get absBalance => balance.abs();
}

// ── Aging Summary ─────────────────────────────────────────────────────────────
class AgingSummary {
  final double current;
  final double days1to30;
  final double days31to60;
  final double days61to90;
  final double days90plus;

  const AgingSummary({
    this.current   = 0,
    this.days1to30 = 0,
    this.days31to60= 0,
    this.days61to90= 0,
    this.days90plus= 0,
  });

  double get total => current + days1to30 + days31to60 + days61to90 + days90plus;
}
