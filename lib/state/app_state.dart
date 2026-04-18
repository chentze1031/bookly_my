import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../constants.dart';
import '../services/db_service.dart';
import '../services/fx_service.dart';
import '../services/supabase_service.dart';

enum SyncStatus { idle, pulling, pushing, done, error }
enum FxStatus   { idle, loading, ok, error }

class AppState extends ChangeNotifier {
  // ── Data ─────────────────────────────────────────────────────────────────────
  List<Transaction> txs      = [];
  List<Customer>    customers = [];
  List<Employee>    employees = [];
  AppSettings       settings  = const AppSettings();
  Map<String, double> fxRates = Map.from(defaultRates);

  // ── Status ───────────────────────────────────────────────────────────────────
  FxStatus   fxStatus   = FxStatus.idle;
  String?    fxUpdatedAt;
  SyncStatus syncStatus = SyncStatus.idle;
  String?    syncError;
  bool       loading    = true;

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    // Load cached FX
    fxRates = await FxService.loadCached();
    // Load from SQLite
    txs       = await DbService.loadTxs();
    customers = await DbService.loadCustomers();
    employees = await DbService.loadEmployees();
    // Load settings from prefs
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('bly_settings');
    if (raw != null) settings = AppSettings.fromMap(jsonDecode(raw));
    loading = false;
    notifyListeners();
    // Fetch live FX in background
    fetchFxRates();
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bly_settings', jsonEncode(s.toMap()));
    notifyListeners();
  }

  // ── FX ────────────────────────────────────────────────────────────────────────
  Future<void> fetchFxRates() async {
    fxStatus = FxStatus.loading;
    notifyListeners();
    final result = await FxService.fetchLive();
    if (result != null) {
      fxRates = result;
      fxStatus = FxStatus.ok;
      fxUpdatedAt = _timeStr();
    } else {
      fxStatus = FxStatus.error;
    }
    notifyListeners();
  }

  void setFxRate(String code, double val) {
    fxRates = {...fxRates, code: val};
    notifyListeners();
  }

  void resetFxRates() {
    fxRates = Map.from(defaultRates);
    notifyListeners();
  }

  double toMYR(double amount, String currency) =>
    amount * (fxRates[currency] ?? 1.0);

  // ── Transactions ─────────────────────────────────────────────────────────────
  Future<void> addOrUpdateTx(Transaction tx) async {
    await DbService.upsertTx(tx);
    final idx = txs.indexWhere((t) => t.id == tx.id);
    if (idx >= 0) {
      txs = [...txs.sublist(0, idx), tx, ...txs.sublist(idx + 1)];
    } else {
      txs = [tx, ...txs];
    }
    txs.sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
  }

  Future<void> deleteTx(int id) async {
    await DbService.deleteTx(id);
    txs = txs.where((t) => t.id != id).toList();
    notifyListeners();
  }

  // ── Customers ────────────────────────────────────────────────────────────────
  Future<Customer> saveCustomer(Customer c) async {
    final saved = await DbService.upsertCustomer(c);
    final idx = customers.indexWhere((x) => x.id == saved.id);
    if (idx >= 0) {
      customers = [...customers.sublist(0, idx), saved, ...customers.sublist(idx + 1)];
    } else {
      customers = [...customers, saved];
    }
    customers.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return saved;
  }

  Future<void> deleteCustomer(int id) async {
    await DbService.deleteCustomer(id);
    customers = customers.where((c) => c.id != id).toList();
    notifyListeners();
  }

  // ── Employees ────────────────────────────────────────────────────────────────
  Future<Employee> saveEmployee(Employee e) async {
    final saved = await DbService.upsertEmployee(e);
    final idx = employees.indexWhere((x) => x.id == saved.id);
    if (idx >= 0) {
      employees = [...employees.sublist(0, idx), saved, ...employees.sublist(idx + 1)];
    } else {
      employees = [...employees, saved];
    }
    employees.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return saved;
  }

  Future<void> deleteEmployee(int id) async {
    await DbService.deleteEmployee(id);
    employees = employees.where((e) => e.id != id).toList();
    notifyListeners();
  }

  // ── Cloud ────────────────────────────────────────────────────────────────────
  Future<bool> pullCloud() async {
    syncStatus = SyncStatus.pulling; syncError = null;
    notifyListeners();
    try {
      final remote = await SupabaseService.loadTxs();
      // Merge: remote wins for same id, keep local-only
      final remoteMap = {for (final tx in remote) tx.id: tx};
      final localOnly = txs.where((t) => !remoteMap.containsKey(t.id)).toList();
      final merged = [...remote, ...localOnly]..sort((a,b)=>b.date.compareTo(a.date));
      // Write all to SQLite
      await DbService.clearTxs();
      for (final tx in merged) await DbService.upsertTx(tx);
      txs = merged;

      final remoteS = await SupabaseService.loadSettings();
      if (remoteS != null) settings = AppSettings.fromMap(remoteS);

      syncStatus = SyncStatus.done;
      notifyListeners();
      return true;
    } catch (e) {
      syncStatus = SyncStatus.error;
      syncError  = e.toString().substring(0, 60.clamp(0, e.toString().length));
      notifyListeners();
      return false;
    }
  }

  Future<bool> pushCloud() async {
    syncStatus = SyncStatus.pushing; syncError = null;
    notifyListeners();
    try {
      await SupabaseService.upsertTxs(txs);
      await SupabaseService.saveSettings(settings.toMap());
      syncStatus = SyncStatus.done;
      notifyListeners();
      return true;
    } catch (e) {
      syncStatus = SyncStatus.error;
      syncError  = e.toString().substring(0, 60.clamp(0, e.toString().length));
      notifyListeners();
      return false;
    }
  }

  // ── Ledger helpers ───────────────────────────────────────────────────────────
  Map<String, double> computeBalances([List<Transaction>? source]) {
    final list = source ?? txs;
    final b = <String, double>{for (final k in accounts.keys) k: 0.0};
    for (final tx in list) {
      for (final e in tx.entries) {
        final acc = accounts[e.acc];
        if (acc == null) continue;
        final dr = acc.normal == 'Dr';
        b[e.acc] = (b[e.acc] ?? 0) + (dr ? (e.dc == 'Dr' ? e.val : -e.val)
                                          : (e.dc == 'Cr' ? e.val : -e.val));
      }
    }
    return b;
  }

  // ── Month helpers ─────────────────────────────────────────────────────────────
  String get currentMonth => DateTime.now().toIso8601String().substring(0, 7);

  List<Transaction> get thisMonthTxs =>
    txs.where((t) => t.date.startsWith(currentMonth)).toList();

  List<String> get availableMonths =>
    txs.map((t) => t.date.substring(0, 7)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

  // ─── Util ─────────────────────────────────────────────────────────────────────
  String _timeStr() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}';
  }
}
