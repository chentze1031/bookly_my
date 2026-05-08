import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import '../constants.dart';
import '../services/db_service.dart';
import '../services/fx_service.dart';
import '../services/supabase_service.dart';

enum SyncStatus { idle, pulling, pushing, done, error }
enum FxStatus   { idle, loading, ok, error }

class AppState extends ChangeNotifier {
  // ── Data ─────────────────────────────────────────────────────────────────────
  List<Transaction> txs       = [];
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

  // ── Supabase client shortcut ─────────────────────────────────────────────────
  static final _sb  = Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;
  bool get _loggedIn => _uid != null;

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
    // Pull cloud data if logged in
    if (_loggedIn) pullCloud();
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bly_settings', jsonEncode(s.toMap()));
    notifyListeners();
    if (_loggedIn) _pushSettingsCloud();
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
    // ✅ Push to cloud
    if (_loggedIn) _pushTxCloud(tx);
  }

  Future<void> deleteTx(int id) async {
    await DbService.deleteTx(id);
    txs = txs.where((t) => t.id != id).toList();
    notifyListeners();
    // ✅ Delete from cloud
    if (_loggedIn) _deleteTxCloud(id);
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
    // ✅ Push to cloud
    if (_loggedIn) _pushCustomerCloud(saved);
    return saved;
  }

  Future<void> deleteCustomer(int id) async {
    await DbService.deleteCustomer(id);
    customers = customers.where((c) => c.id != id).toList();
    notifyListeners();
    // ✅ Delete from cloud
    if (_loggedIn) _deleteCustomerCloud(id);
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
    // ✅ Push to cloud
    if (_loggedIn) _pushEmployeeCloud(saved);
    return saved;
  }

  Future<void> deleteEmployee(int id) async {
    await DbService.deleteEmployee(id);
    employees = employees.where((e) => e.id != id).toList();
    notifyListeners();
    // ✅ Delete from cloud
    if (_loggedIn) _deleteEmployeeCloud(id);
  }

  // ── Invoice save (SharedPreferences + Supabase) ───────────────────────────────
  Future<void> saveInvoice({
    required String invNo,
    required String invDate,
    required String dueDate,
    required Customer customer,
    required List<Map<String, String>> items,
    required String notes,
    required String terms,
    required String bankName,
    required String bankAcct,
    String? logoB64,
    String? sigB64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_invoices') ?? '[]';
    final list  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final record = {
      'invNo':    invNo,
      'invDate':  invDate,
      'dueDate':  dueDate,
      'customer': customer.toMap(),
      'items':    items,
      'notes':    notes,
      'terms':    terms,
      'bankName': bankName,
      'bankAcct': bankAcct,
      'savedAt':  DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['invNo'] == invNo);
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.insert(0, record);
    }
    await prefs.setString('bly_invoices', jsonEncode(list));
    // ✅ Push invoices to cloud
    if (_loggedIn) _pushInvoicesCloud(list);
  }

  // ── Payroll save (SharedPreferences + Supabase) ───────────────────────────────
  Future<void> savePayroll({
    required Employee emp,
    required int month,
    required int year,
    required List<Map<String, String>> earnings,
    required List<Map<String, String>> deductions,
    required bool useEPF,
    required bool useSOCSO,
    required bool useEIS,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_payrolls') ?? '[]';
    final list  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final key   = '${emp.id}_${year}_$month';
    final record = {
      'key':        key,
      'empId':      emp.id,
      'empName':    emp.name,
      'month':      month,
      'year':       year,
      'earnings':   earnings,
      'deductions': deductions,
      'useEPF':     useEPF,
      'useSOCSO':   useSOCSO,
      'useEIS':     useEIS,
      'savedAt':    DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['key'] == key);
    if (idx >= 0) {
      list[idx] = record;
    } else {
      list.insert(0, record);
    }
    await prefs.setString('bly_payrolls', jsonEncode(list));
    // ✅ Push payrolls to cloud
    if (_loggedIn) _pushPayrollsCloud(list);
  }

  // ── Cloud pull (called on login / init) ──────────────────────────────────────
  Future<bool> pullCloud() async {
    syncStatus = SyncStatus.pulling; syncError = null;
    notifyListeners();
    try {
      final uid = _uid!;

      // Transactions
      final remoteTxs = await SupabaseService.loadTxs();
      final remoteMap = {for (final tx in remoteTxs) tx.id: tx};
      final localOnly = txs.where((t) => !remoteMap.containsKey(t.id)).toList();
      final merged = [...remoteTxs, ...localOnly]..sort((a,b)=>b.date.compareTo(a.date));
      await DbService.clearTxs();
      for (final tx in merged) await DbService.upsertTx(tx);
      txs = merged;

      // Customers
      final remoteCusts = await _sb.from('customers').select().eq('user_id', uid);
      if ((remoteCusts as List).isNotEmpty) {
        for (final row in remoteCusts) {
          await DbService.upsertCustomer(Customer.fromMap(row));
        }
        customers = await DbService.loadCustomers();
      }

      // Employees
      final remoteEmps = await _sb.from('employees').select().eq('user_id', uid);
      if ((remoteEmps as List).isNotEmpty) {
        for (final row in remoteEmps) {
          await DbService.upsertEmployee(Employee.fromMap(row));
        }
        employees = await DbService.loadEmployees();
      }

      // Invoices (stored as JSON blob in Supabase user_data table)
      final invRow = await _sb.from('user_data')
          .select('invoices').eq('user_id', uid).maybeSingle();
      if (invRow != null && invRow['invoices'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bly_invoices', jsonEncode(invRow['invoices']));
      }

      // Payrolls
      final payRow = await _sb.from('user_data')
          .select('payrolls').eq('user_id', uid).maybeSingle();
      if (payRow != null && payRow['payrolls'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('bly_payrolls', jsonEncode(payRow['payrolls']));
      }

      // Settings
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
      // Also push customers & employees
      final uid = _uid;
      if (uid != null) {
        for (final c in customers) await _pushCustomerCloud(c);
        for (final e in employees) await _pushEmployeeCloud(e);
      }
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

  // ── Private cloud helpers (fire-and-forget) ───────────────────────────────────
  Future<void> _pushTxCloud(Transaction tx) async {
    try {
      await _sb.from('transactions').upsert({
        ...tx.toMap(), 'user_id': _uid,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id,user_id');
    } catch (_) {}
  }

  Future<void> _deleteTxCloud(int id) async {
    try {
      await _sb.from('transactions').delete().eq('id', id).eq('user_id', _uid!);
    } catch (_) {}
  }

  Future<void> _pushCustomerCloud(Customer c) async {
    try {
      await _sb.from('customers').upsert({
        ...c.toMap(), 'user_id': _uid,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id,user_id');
    } catch (_) {}
  }

  Future<void> _deleteCustomerCloud(int id) async {
    try {
      await _sb.from('customers').delete().eq('id', id).eq('user_id', _uid!);
    } catch (_) {}
  }

  Future<void> _pushEmployeeCloud(Employee e) async {
    try {
      await _sb.from('employees').upsert({
        ...e.toMap(), 'user_id': _uid,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id,user_id');
    } catch (_) {}
  }

  Future<void> _deleteEmployeeCloud(int id) async {
    try {
      await _sb.from('employees').delete().eq('id', id).eq('user_id', _uid!);
    } catch (_) {}
  }

  Future<void> _pushInvoicesCloud(List list) async {
    try {
      await _sb.from('user_data').upsert({
        'user_id': _uid,
        'invoices': list,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }

  Future<void> _pushPayrollsCloud(List list) async {
    try {
      await _sb.from('user_data').upsert({
        'user_id': _uid,
        'payrolls': list,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (_) {}
  }

  Future<void> _pushSettingsCloud() async {
    try {
      await SupabaseService.saveSettings(settings.toMap());
    } catch (_) {}
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

  // ── Util ─────────────────────────────────────────────────────────────────────
  String _timeStr() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}';
  }

  // ── Invoice history load/delete ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> loadInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_invoices') ?? '[]';
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteInvoice(String invNo) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_invoices') ?? '[]';
    final list  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['invNo'] == invNo);
    await prefs.setString('bly_invoices', jsonEncode(list));
    if (_loggedIn) _pushInvoicesCloud(list);
  }

  // ── Payroll history load/delete ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> loadPayrolls() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_payrolls') ?? '[]';
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> deletePayroll(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('bly_payrolls') ?? '[]';
    final list  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['key'] == key);
    await prefs.setString('bly_payrolls', jsonEncode(list));
    if (_loggedIn) _pushPayrollsCloud(list);
  }
}
