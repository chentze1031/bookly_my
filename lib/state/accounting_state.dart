import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accounting_models.dart';
import '../constants.dart';
import '../models.dart';
import 'app_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// ACCOUNTING STATE
// ════════════════════════════════════════════════════════════════════════════
class AccountingState extends ChangeNotifier {
  List<ArInvoice> arInvoices = [];
  List<ApBill>    apBills    = [];
  List<Supplier>  suppliers  = [];
  bool            loading    = false;

  // ── AppState link for GL sync ─────────────────────────────────────────────
  AppState? appState;

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kAr  = 'bly_ar_invoices';
  static const _kAp  = 'bly_ap_bills';
  static const _kSup = 'bly_suppliers';

  // ── Summary getters ───────────────────────────────────────────────────────
  double get totalReceivable => arInvoices.fold(0, (s, i) => s + i.balance);
  double get totalPayable    => apBills.fold(0, (s, b) => s + b.balance);
  int    get overdueArCount  => arInvoices.where((i) => i.isOverdue).length;
  int    get overdueApCount  => apBills.where((b) => b.isOverdue).length;

  double get totalOverdueAr =>
    arInvoices.where((i) => i.isOverdue).fold(0, (s, i) => s + i.balance);
  double get totalOverdueAp =>
    apBills.where((b) => b.isOverdue).fold(0, (s, b) => s + b.balance);

  // ── Stable TX id helpers ──────────────────────────────────────────────────
  // Phase 1: Invoice/Bill creation  → affects P&L (income/expense)
  // Phase 2: Payment collection/made → affects Balance Sheet only (transfer)
  // Using fixed offsets ensures editing = upsert, not duplicate.
  static int _arInvTxId(int arId)  => arId + 1000000000000; // AR phase 1
  static int _apBillTxId(int apId) => apId + 2000000000000; // AP phase 1
  // Phase-2 payments use a composite id: base + cumulative paid cents
  // This means each new partial payment gets its own stable id.
  static int _arPayTxId(int arId, double paidAfter) =>
      arId + 3000000000000 + (paidAfter * 100).round();
  static int _apPayTxId(int apId, double paidAfter) =>
      apId + 4000000000000 + (paidAfter * 100).round();

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    loading = true; notifyListeners();
    final prefs = await SharedPreferences.getInstance();

    final arRaw = prefs.getString(_kAr) ?? '[]';
    arInvoices = (jsonDecode(arRaw) as List)
      .map((m) => ArInvoice.fromMap(m as Map<String, dynamic>))
      .toList();

    final apRaw = prefs.getString(_kAp) ?? '[]';
    apBills = (jsonDecode(apRaw) as List)
      .map((m) => ApBill.fromMap(m as Map<String, dynamic>))
      .toList();

    final supRaw = prefs.getString(_kSup) ?? '[]';
    suppliers = (jsonDecode(supRaw) as List)
      .map((m) => Supplier.fromMap(m as Map<String, dynamic>))
      .toList();

    _refreshOverdueStatuses();
    loading = false; notifyListeners();
  }

  void _refreshOverdueStatuses() {
    arInvoices = arInvoices.map((inv) {
      if (inv.isOverdue && inv.status == InvoiceStatus.sent) {
        return inv.copyWith(status: InvoiceStatus.overdue);
      }
      return inv;
    }).toList();
    apBills = apBills.map((bill) {
      if (bill.isOverdue && bill.status == InvoiceStatus.sent) {
        return bill.copyWith(status: InvoiceStatus.overdue);
      }
      return bill;
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════════════
  // AR INVOICE CRUD
  // ════════════════════════════════════════════════════════════════════════

  Future<void> saveArInvoice(ArInvoice inv) async {
    final idx = arInvoices.indexWhere((i) => i.id == inv.id);
    if (idx >= 0) {
      arInvoices = [...arInvoices.sublist(0, idx), inv, ...arInvoices.sublist(idx + 1)];
    } else {
      arInvoices = [inv, ...arInvoices];
    }
    arInvoices.sort((a, b) => b.issueDate.compareTo(a.issueDate));
    await _persistAr();

    // ── Phase 1 GL: Dr 1100 AR / Cr 4010 Revenue ─────────────────────────
    // Records revenue the moment invoice is issued (accrual basis).
    // P&L immediately shows income. Balance Sheet shows AR asset.
    // Stable id → editing invoice = upsert, never duplicate.
    if (appState != null) {
      await appState!.addOrUpdateTx(Transaction(
        id:           _arInvTxId(inv.id),
        type:         'income',           // → appears in P&L Revenue
        catId:        'ar_invoice',
        amountMYR:    inv.total,
        origAmount:   inv.total,
        origCurrency: 'MYR',
        sstKey:       inv.sstAmount > 0 ? 'sst6' : 'none',
        sstMYR:       inv.sstAmount,
        descEN:       'Invoice: ${inv.invNo} – ${inv.customerName}',
        descZH:       '发票: ${inv.invNo} – ${inv.customerName}',
        date:         inv.issueDate,
        entries: [
          JournalEntry(acc: '1100', dc: 'Dr', val: inv.total), // Dr AR
          JournalEntry(acc: '4010', dc: 'Cr', val: inv.total), // Cr Revenue
        ],
      ));
    }

    notifyListeners();
  }

  Future<void> deleteArInvoice(int id) async {
    arInvoices = arInvoices.where((i) => i.id != id).toList();
    await _persistAr();

    // Remove phase-1 invoice TX from GL
    if (appState != null) {
      await appState!.deleteTx(_arInvTxId(id));
      // Note: phase-2 payment TXs are intentionally kept as audit trail.
      // If you want to remove them too, delete TXs where id starts with
      // _arPayTxId range (3000000000000 + id + paid*100).
    }

    notifyListeners();
  }

  Future<void> recordArPayment(int id, double amount) async {
    final idx = arInvoices.indexWhere((i) => i.id == id);
    if (idx < 0) return;
    final inv     = arInvoices[idx];
    final paid    = (inv.amountPaid + amount).clamp(0, inv.total).toDouble();
    final newStat = paid >= inv.total ? InvoiceStatus.paid
                  : paid > 0         ? InvoiceStatus.partial
                  : inv.status;
    arInvoices[idx] = inv.copyWith(amountPaid: paid, status: newStat);
    arInvoices = List.from(arInvoices);
    await _persistAr();

    // ── Phase 2 GL: Dr 1020 Bank / Cr 1100 AR ────────────────────────────
    // Cash received → Bank increases, AR decreases.
    // type = 'transfer': does NOT affect P&L (revenue already in phase 1).
    // This is purely a Balance Sheet internal move.
    if (appState != null) {
      await appState!.addOrUpdateTx(Transaction(
        id:           _arPayTxId(inv.id, paid),
        type:         'transfer',          // → does NOT appear in P&L
        catId:        'ar_collect',
        amountMYR:    amount,
        origAmount:   amount,
        origCurrency: 'MYR',
        sstKey:       'none',
        sstMYR:       0,
        descEN:       'AR Payment: ${inv.invNo} – ${inv.customerName}',
        descZH:       '收款: ${inv.invNo} – ${inv.customerName}',
        date:         DateTime.now().toIso8601String().substring(0, 10),
        entries: [
          JournalEntry(acc: '1020', dc: 'Dr', val: amount), // Dr Bank
          JournalEntry(acc: '1100', dc: 'Cr', val: amount), // Cr AR
        ],
      ));
    }

    notifyListeners();
  }

  Future<void> _persistAr() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAr, jsonEncode(arInvoices.map((i) => i.toMap()).toList()));
  }

  // ════════════════════════════════════════════════════════════════════════
  // AP BILL CRUD
  // ════════════════════════════════════════════════════════════════════════

  Future<void> saveApBill(ApBill bill) async {
    final idx = apBills.indexWhere((b) => b.id == bill.id);
    if (idx >= 0) {
      apBills = [...apBills.sublist(0, idx), bill, ...apBills.sublist(idx + 1)];
    } else {
      apBills = [bill, ...apBills];
    }
    apBills.sort((a, b) => b.issueDate.compareTo(a.issueDate));
    await _persistAp();

    // ── Phase 1 GL: Dr Expense / Cr 2010 AP ──────────────────────────────
    // Records expense the moment bill is received (accrual basis).
    // P&L immediately shows the cost. Balance Sheet shows AP liability.
    // Stable id → editing bill = upsert, never duplicate.
    if (appState != null) {
      final expAcc = _billExpenseAcc(bill.category);
      final catId  = _billCatId(bill.category);
      await appState!.addOrUpdateTx(Transaction(
        id:           _apBillTxId(bill.id),
        type:         'expense',           // → appears in P&L Expenses
        catId:        catId,
        amountMYR:    bill.total,
        origAmount:   bill.total,
        origCurrency: 'MYR',
        sstKey:       bill.sstAmount > 0 ? 'sst6' : 'none',
        sstMYR:       bill.sstAmount,
        descEN:       'Bill: ${bill.billNo} – ${bill.supplierName}',
        descZH:       '账单: ${bill.billNo} – ${bill.supplierName}',
        date:         bill.issueDate,
        entries: [
          JournalEntry(acc: expAcc, dc: 'Dr', val: bill.total), // Dr Expense
          JournalEntry(acc: '2010', dc: 'Cr', val: bill.total), // Cr AP
        ],
      ));
    }

    notifyListeners();
  }

  Future<void> deleteApBill(int id) async {
    apBills = apBills.where((b) => b.id != id).toList();
    await _persistAp();

    // Remove phase-1 bill TX from GL
    if (appState != null) {
      await appState!.deleteTx(_apBillTxId(id));
    }

    notifyListeners();
  }

  Future<void> recordApPayment(int id, double amount) async {
    final idx = apBills.indexWhere((b) => b.id == id);
    if (idx < 0) return;
    final bill    = apBills[idx];
    final paid    = (bill.amountPaid + amount).clamp(0, bill.total).toDouble();
    final newStat = paid >= bill.total ? InvoiceStatus.paid
                  : paid > 0          ? InvoiceStatus.partial
                  : bill.status;
    apBills[idx] = bill.copyWith(amountPaid: paid, status: newStat);
    apBills = List.from(apBills);
    await _persistAp();

    // ── Phase 2 GL: Dr 2010 AP / Cr 1020 Bank ────────────────────────────
    // Cash paid out → AP decreases, Bank decreases.
    // type = 'transfer': does NOT affect P&L (expense already in phase 1).
    // This is purely a Balance Sheet internal move.
    if (appState != null) {
      await appState!.addOrUpdateTx(Transaction(
        id:           _apPayTxId(bill.id, paid),
        type:         'transfer',          // → does NOT appear in P&L
        catId:        'ap_payment',
        amountMYR:    amount,
        origAmount:   amount,
        origCurrency: 'MYR',
        sstKey:       'none',
        sstMYR:       0,
        descEN:       'AP Payment: ${bill.billNo} – ${bill.supplierName}',
        descZH:       '付款: ${bill.billNo} – ${bill.supplierName}',
        date:         DateTime.now().toIso8601String().substring(0, 10),
        entries: [
          JournalEntry(acc: '2010', dc: 'Dr', val: amount), // Dr AP
          JournalEntry(acc: '1020', dc: 'Cr', val: amount), // Cr Bank
        ],
      ));
    }

    notifyListeners();
  }

  Future<void> _persistAp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAp, jsonEncode(apBills.map((b) => b.toMap()).toList()));
  }

  // ── Bill category helpers ─────────────────────────────────────────────────
  String _billExpenseAcc(String? catId) {
    const map = <String, String>{
      'rent':         '5110',
      'salary':       '5100',
      'marketing':    '5140',
      'transport':    '5210',
      'inventory':    '1200',
      'professional': '5180',
      'supplies':     '5130',
      'repairs':      '5190',
      'insurance':    '5150',
    };
    return map[catId] ?? '5200';
  }

  String _billCatId(String? catId) {
    const map = <String, String>{
      'rent':         'rent',
      'salary':       'salary',
      'marketing':    'marketing',
      'transport':    'transport',
      'inventory':    'inventory',
      'professional': 'professional_fees',
      'supplies':     'office_supplies',
      'repairs':      'repairs',
      'insurance':    'insurance',
    };
    return map[catId] ?? 'other_expense';
  }

  // ════════════════════════════════════════════════════════════════════════
  // SUPPLIER CRUD
  // ════════════════════════════════════════════════════════════════════════
  Future<Supplier> saveSupplier(Supplier s) async {
    final withId = s.id == 0
      ? Supplier(
          id:       DateTime.now().millisecondsSinceEpoch,
          name:     s.name, regNo: s.regNo, sstRegNo: s.sstRegNo,
          address:  s.address, phone: s.phone, email: s.email,
          bankName: s.bankName, bankAcct: s.bankAcct,
        )
      : s;

    final idx = suppliers.indexWhere((x) => x.id == withId.id);
    if (idx >= 0) {
      suppliers = [...suppliers.sublist(0, idx), withId, ...suppliers.sublist(idx + 1)];
    } else {
      suppliers = [...suppliers, withId];
    }
    suppliers.sort((a, b) => a.name.compareTo(b.name));
    await _persistSuppliers();
    notifyListeners();
    return withId;
  }

  Future<void> deleteSupplier(int id) async {
    suppliers = suppliers.where((s) => s.id != id).toList();
    await _persistSuppliers();
    notifyListeners();
  }

  Future<void> _persistSuppliers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSup, jsonEncode(suppliers.map((s) => s.toMap()).toList()));
  }

  // ════════════════════════════════════════════════════════════════════════
  // AGING ANALYSIS
  // ════════════════════════════════════════════════════════════════════════
  AgingSummary get arAgingSummary {
    double cur = 0, d30 = 0, d60 = 0, d90 = 0, d90p = 0;
    for (final inv in arInvoices) {
      if (inv.status == InvoiceStatus.paid || inv.status == InvoiceStatus.void_) continue;
      final b = inv.balance;
      switch (inv.agingBucket) {
        case 'Current':    cur  += b;
        case '1-30 days':  d30  += b;
        case '31-60 days': d60  += b;
        case '61-90 days': d90  += b;
        case '90+ days':   d90p += b;
      }
    }
    return AgingSummary(current: cur, days1to30: d30, days31to60: d60, days61to90: d90, days90plus: d90p);
  }

  AgingSummary get apAgingSummary {
    double cur = 0, d30 = 0, d60 = 0, d90 = 0, d90p = 0;
    for (final bill in apBills) {
      if (bill.status == InvoiceStatus.paid || bill.status == InvoiceStatus.void_) continue;
      final b = bill.balance;
      switch (bill.agingBucket) {
        case 'Current':    cur  += b;
        case '1-30 days':  d30  += b;
        case '31-60 days': d60  += b;
        case '61-90 days': d90  += b;
        case '90+ days':   d90p += b;
      }
    }
    return AgingSummary(current: cur, days1to30: d30, days31to60: d60, days61to90: d90, days90plus: d90p);
  }

  // ── Filter helpers ────────────────────────────────────────────────────────
  List<ArInvoice> arByStatus(InvoiceStatus? status) =>
    status == null ? arInvoices : arInvoices.where((i) => i.status == status).toList();

  List<ApBill> apByStatus(InvoiceStatus? status) =>
    status == null ? apBills : apBills.where((b) => b.status == status).toList();
}
