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

  // ── Link to AppState for GL sync ─────────────────────────────────────────
  AppState? appState;

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kAr  = 'bly_ar_invoices';
  static const _kAp  = 'bly_ap_bills';
  static const _kSup = 'bly_suppliers';

  // ── Summary getters ───────────────────────────────────────────────────────
  double get totalReceivable  => arInvoices.fold(0, (s, i) => s + i.balance);
  double get totalPayable     => apBills.fold(0, (s, b) => s + b.balance);
  int    get overdueArCount   => arInvoices.where((i) => i.isOverdue).length;
  int    get overdueApCount   => apBills.where((b) => b.isOverdue).length;

  double get totalOverdueAr   =>
    arInvoices.where((i) => i.isOverdue).fold(0, (s, i) => s + i.balance);
  double get totalOverdueAp   =>
    apBills.where((b) => b.isOverdue).fold(0, (s, b) => s + b.balance);

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    loading = true; notifyListeners();
    final prefs = await SharedPreferences.getInstance();

    // AR
    final arRaw = prefs.getString(_kAr) ?? '[]';
    arInvoices = (jsonDecode(arRaw) as List)
      .map((m) => ArInvoice.fromMap(m as Map<String, dynamic>))
      .toList();

    // AP
    final apRaw = prefs.getString(_kAp) ?? '[]';
    apBills = (jsonDecode(apRaw) as List)
      .map((m) => ApBill.fromMap(m as Map<String, dynamic>))
      .toList();

    // Suppliers
    final supRaw = prefs.getString(_kSup) ?? '[]';
    suppliers = (jsonDecode(supRaw) as List)
      .map((m) => Supplier.fromMap(m as Map<String, dynamic>))
      .toList();

    // Auto-update overdue statuses
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
    notifyListeners();
  }

  Future<void> deleteArInvoice(int id) async {
    arInvoices = arInvoices.where((i) => i.id != id).toList();
    await _persistAr();
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

    // ── Sync to GL: Dr 1020 Bank / Cr 1100 AR ────────────────────────────
    await _syncArPaymentToGl(inv: inv, amount: amount);

    notifyListeners();
  }

  Future<void> _syncArPaymentToGl({required ArInvoice inv, required double amount}) async {
    if (appState == null) return;
    final cat = findCat('ar_collect'); // Dr Bank / Cr AR
    if (cat == null) return;
    final tx = Transaction(
      id:           DateTime.now().millisecondsSinceEpoch,
      type:         'income',
      catId:        'ar_collect',
      amountMYR:    amount,
      origAmount:   amount,
      origCurrency: 'MYR',
      sstKey:       'none',
      sstMYR:       0,
      descEN:       'AR Payment: ${inv.invNo} - ${inv.customerName}',
      descZH:       '收款: ${inv.invNo} - ${inv.customerName}',
      date:         DateTime.now().toIso8601String().substring(0, 10),
      entries:      cat.mkEntries(amount),
    );
    await appState!.addOrUpdateTx(tx);
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
    notifyListeners();
  }

  Future<void> deleteApBill(int id) async {
    apBills = apBills.where((b) => b.id != id).toList();
    await _persistAp();
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

    // ── Sync to GL: Dr 2010 AP / Cr 1020 Bank ────────────────────────────
    await _syncApPaymentToGl(bill: bill, amount: amount);

    notifyListeners();
  }

  Future<void> _syncApPaymentToGl({required ApBill bill, required double amount}) async {
    if (appState == null) return;
    final cat = findCat('ap_payment'); // Dr AP / Cr Bank
    if (cat == null) return;
    final tx = Transaction(
      id:           DateTime.now().millisecondsSinceEpoch,
      type:         'expense',
      catId:        'ap_payment',
      amountMYR:    amount,
      origAmount:   amount,
      origCurrency: 'MYR',
      sstKey:       'none',
      sstMYR:       0,
      descEN:       'AP Payment: ${bill.billNo} - ${bill.supplierName}',
      descZH:       '付款: ${bill.billNo} - ${bill.supplierName}',
      date:         DateTime.now().toIso8601String().substring(0, 10),
      entries:      cat.mkEntries(amount),
    );
    await appState!.addOrUpdateTx(tx);
  }

  Future<void> _persistAp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAp, jsonEncode(apBills.map((b) => b.toMap()).toList()));
  }

  // ════════════════════════════════════════════════════════════════════════
  // SUPPLIER CRUD
  // ════════════════════════════════════════════════════════════════════════
  Future<Supplier> saveSupplier(Supplier s) async {
    final sup = s.id == 0
      ? s.copyWith() // new — id assigned below
      : s;
    final withId = sup.id == 0
      ? Supplier(
          id:       DateTime.now().millisecondsSinceEpoch,
          name:     sup.name, regNo: sup.regNo, sstRegNo: sup.sstRegNo,
          address:  sup.address, phone: sup.phone, email: sup.email,
          bankName: sup.bankName, bankAcct: sup.bankAcct,
        )
      : sup;

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
