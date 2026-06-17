import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models.dart';
import '../constants.dart';
import '../utils.dart';
import '../services/db_service.dart';
import '../services/fx_service.dart';
import '../services/settings_service.dart';
import '../services/supabase_service.dart';
import '../services/widget_service.dart';

enum SyncStatus { idle, pulling, pushing, done, error }
enum FxStatus   { idle, loading, ok, error }

class _QueuedOp {
  final String table;
  final String op;
  final Map<String, dynamic>? data;
  final int? id;
  final String companyId; // company this op belongs to (Phase 4 #24)
  final DateTime queuedAt;
  _QueuedOp({required this.table, required this.op, this.data, this.id,
      String? companyId})
    : companyId = companyId ?? activeCompanyId,
      queuedAt = DateTime.now();

  Map<String, dynamic> toMap() => {
    'table': table, 'op': op, 'data': data, 'id': id, 'companyId': companyId,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory _QueuedOp.fromMap(Map<String, dynamic> m) => _QueuedOp(
    table: m['table'], op: m['op'],
    data: m['data'] != null ? Map<String, dynamic>.from(m['data']) : null,
    id: m['id'],
    companyId: m['companyId'] as String? ?? 'default',
  );
}

class AppState extends ChangeNotifier {
  List<Transaction> txs       = [];
  List<Customer>    customers = [];
  List<Employee>    employees = [];
  AppSettings       settings  = const AppSettings();
  Map<String, double> fxRates = Map.from(defaultRates);

  // ── Multi-company (Phase 4 #24) ───────────────────────────────────────────
  List<Company> companies     = [];
  String        activeCompany = 'default';
  Company get activeCompanyObj =>
      companies.firstWhere((c) => c.id == activeCompany,
          orElse: () => const Company(id: 'default', name: 'My Company'));
  // Cloud sync runs whenever logged in; every row is tagged with company_id so
  // each company stays isolated in the cloud too (Phase 4 #24 cloud phase).
  bool get _cloudOn => _loggedIn;

  FxStatus   fxStatus   = FxStatus.idle;
  String?    fxUpdatedAt;
  SyncStatus syncStatus = SyncStatus.idle;
  String?    syncError;
  bool       loading    = true;
  bool       isOnline   = true;
  int        pendingOps = 0;

  final List<_QueuedOp> _queue = [];

  static final _sb  = Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;
  bool get _loggedIn => _uid != null;

  // ── Init ─────────────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    // Multi-company: resolve the active company BEFORE any scoped / SQLite read.
    await _initCompanies(prefs);
    fxRates   = await FxService.loadCached();
    txs       = await DbService.loadTxs();
    customers = await DbService.loadCustomers();
    employees = await DbService.loadEmployees();
    settings = await SettingsService.load();
    await _syncActiveCompanyName();
    final q = prefs.getString(StorageKeys.offlineQueue);
    if (q != null) {
      final list = (jsonDecode(q) as List);
      _queue.addAll(list.map((e) => _QueuedOp.fromMap(Map<String, dynamic>.from(e))));
      pendingOps = _queue.length;
    }
    loading = false;
    notifyListeners();
    fetchFxRates();
    // FIX: 不在 init 里调 pullCloud()，避免与 AuthGate.syncOnLogin() 并发竞跑。
    // 云端同步统一由 AuthGate 在 signedIn / initialSession 事件后触发。
    if (_cloudOn) await _flushQueue();
    await updateHomeWidget();
  }

  // ── Multi-company registry (Phase 4 #24) ──────────────────────────────────────
  Future<void> _initCompanies(SharedPreferences prefs) async {
    final raw = prefs.getString(StorageKeys.companies);
    companies = raw != null
        ? (jsonDecode(raw) as List)
            .map((m) => Company.fromMap(Map<String, dynamic>.from(m)))
            .toList()
        : [];
    if (companies.isEmpty) {
      companies = [const Company(id: 'default', name: 'My Company')];
      await _saveCompanies(prefs);
    }
    activeCompany = prefs.getString(StorageKeys.activeCompany) ?? 'default';
    if (!companies.any((c) => c.id == activeCompany)) activeCompany = 'default';
    applyActiveCompany(activeCompany);
  }

  Future<void> _saveCompanies([SharedPreferences? p]) async {
    final prefs = p ?? await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.companies,
        jsonEncode(companies.map((c) => c.toMap()).toList()));
  }

  /// Keep the active company's registry name in step with its company-info name.
  Future<void> _syncActiveCompanyName() async {
    final name = settings.companyName.trim();
    if (name.isEmpty) return;
    final idx = companies.indexWhere((c) => c.id == activeCompany);
    if (idx >= 0 && companies[idx].name != name) {
      companies[idx] = Company(id: activeCompany, name: name);
      await _saveCompanies();
      notifyListeners();
    }
  }

  /// Reload all of this AppState's per-company data (after a company switch).
  Future<void> _reloadCompanyData() async {
    txs       = await DbService.loadTxs();
    customers = await DbService.loadCustomers();
    employees = await DbService.loadEmployees();
    settings  = await SettingsService.load();
    filterFrom = null; filterTo = null; // company-specific view resets
  }

  /// Switch the active company. Caller must also reload AccountingState /
  /// InventoryState (they hold their own per-company data).
  Future<void> switchCompany(String id) async {
    if (id == activeCompany || !companies.any((c) => c.id == id)) return;
    activeCompany = id;
    applyActiveCompany(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.activeCompany, id);
    await DbService.reset();            // reopen the right SQLite file
    await _reloadCompanyData();
    notifyListeners();
    await updateHomeWidget();
    // Merge this company's cloud data (all rows are company_id-scoped now).
    if (_cloudOn) { await _flushQueue(); await pullCloud(); }
  }

  /// Create a new (empty) company and return its id.
  Future<String> createCompany(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final nm = name.trim().isEmpty ? 'Company' : name.trim();
    companies = [...companies, Company(id: id, name: nm)];
    await _saveCompanies();
    notifyListeners();
    return id;
  }

  Future<void> renameCompany(String id, String name) async {
    final idx = companies.indexWhere((c) => c.id == id);
    if (idx < 0 || name.trim().isEmpty) return;
    companies[idx] = Company(id: id, name: name.trim());
    companies = [...companies];
    await _saveCompanies();
    notifyListeners();
  }

  /// Delete a non-default company: removes its registry entry and purges all of
  /// its device-local data (scoped prefs + SQLite file).
  Future<void> deleteCompany(String id) async {
    if (id == 'default') return;
    companies = companies.where((c) => c.id != id).toList();
    await _saveCompanies();
    if (_loggedIn) await _deleteCompanyCloud(id);
    await _purgeCompanyData(id);
    if (activeCompany == id) {
      activeCompany = 'default';
      applyActiveCompany('default');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageKeys.activeCompany, 'default');
      await DbService.reset();
      await _reloadCompanyData();
      notifyListeners();
      if (_cloudOn) await pullCloud();
    } else {
      notifyListeners();
    }
  }

  /// Delete all of a company's cloud rows (best-effort).
  Future<void> _deleteCompanyCloud(String id) async {
    const tables = ['transactions', 'customers', 'employees', 'inventory',
        'stock_movements', 'user_data', 'user_settings'];
    for (final t in tables) {
      try { await _sb.from(t).delete().eq('user_id', _uid!).eq('company_id', id); } catch (_) {}
    }
  }

  Future<void> _purgeCompanyData(String id) async {
    final prefs = await SharedPreferences.getInstance();
    const bases = [
      'bly_settings', 'bly_invoices', 'bly_payrolls', 'bly_ar_invoices',
      'bly_quotations', 'bly_delivery_orders', 'bly_credit_notes', 'bly_leave',
      'bly_purchase_orders', 'bly_budgets', 'bly_recurring', 'bly_warehouses',
      'bly_ap_bills', 'bly_suppliers',
    ];
    for (final b in bases) {
      await prefs.remove('${b}__$id');
    }
    try { await deleteDatabase(join(await getDatabasesPath(), 'bookly__$id.db')); } catch (_) {}
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────────
  /// 登出。返回 true=本地数据已安全上云后清除；false=推送失败，本地数据已保留。
  Future<bool> signOut() async {
    // FIX(数据丢失): 登出前先把本地数据推到云端，确认成功后才清本地。
    // 推送失败则【不清除】本地数据，避免永久丢失。
    // 多公司(#24): 每家公司在切换为活动时即实时同步，云端已是最新；这里只需
    // 推送/清理当前活动公司的本地缓存，其余公司的本地缓存原样保留。
    bool pushedOk = true;
    if (_loggedIn) {
      try {
        await _flushQueue();
        final ok1 = await pushCloud();              // txs + customers + employees + settings
        final prefs0 = await SharedPreferences.getInstance();
        final invList = jsonDecode(prefs0.getString(StorageKeys.invoices) ?? '[]') as List;
        final payList = jsonDecode(prefs0.getString(StorageKeys.payrolls) ?? '[]') as List;
        if (invList.isNotEmpty) await _pushInvoicesCloud(invList);
        if (payList.isNotEmpty) await _pushPayrollsCloud(payList);
        pushedOk = ok1;
      } catch (_) {
        pushedOk = false;
      }
    }

    await _sb.auth.signOut();

    // 只有确认数据已上云，才清除本地；否则保留本地数据等下次登录再同步。
    if (pushedOk) {
      await DbService.clearTxs();
      txs = []; customers = []; employees = [];
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.invoices);
      await prefs.remove(StorageKeys.payrolls);
      await prefs.remove(StorageKeys.offlineQueue);
      _queue.clear();
      pendingOps = 0;
    }
    notifyListeners();
    return pushedOk;
  }

  /// 登录成功后调用：合并本地数据与云端数据。
  /// pullCloud() 内部已处理本地独有记录的上传，不需要先单独 push。
  Future<void> syncOnLogin() async {
    if (!_cloudOn) return; // non-default companies are device-local
    await _flushQueue();
    // pullCloud() 内部：本地有、云端没有的 → 推上云；云端有的 → 拉下来合并。
    // 失败时保留现有本地数据，不清空。
    await pullCloud();
  }

  // ── Settings ─────────────────────────────────────────────────────────────────
  Future<void> updateSettings(AppSettings s) async {
    settings = s;
    await SettingsService.save(s);
    await _syncActiveCompanyName(); // reflect company-name change in the switcher
    notifyListeners();
    await updateHomeWidget(); // company name / language may have changed
    if (_cloudOn) _pushSettingsCloud();
  }

  // ── FX ────────────────────────────────────────────────────────────────────────
  Future<void> fetchFxRates() async {
    fxStatus = FxStatus.loading;
    notifyListeners();
    final result = await FxService.fetchLive();
    if (result != null) {
      fxRates = result; fxStatus = FxStatus.ok;
      fxUpdatedAt = _timeStr(); isOnline = true;
    } else {
      fxStatus = FxStatus.error; isOnline = false;
    }
    notifyListeners();
  }

  void setFxRate(String code, double val) { fxRates = {...fxRates, code: val}; notifyListeners(); }
  void resetFxRates() { fxRates = Map.from(defaultRates); notifyListeners(); }
  double toMYR(double amount, String currency) => amount * (fxRates[currency] ?? 1.0);

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
    await updateHomeWidget();
    if (_cloudOn) {
      final ok = await _tryPushTxCloud(tx);
      if (!ok) _enqueue(_QueuedOp(table: 'transactions', op: 'upsert', data: tx.toMap()));
    }
  }

  Future<void> deleteTx(int id) async {
    await DbService.deleteTx(id);
    txs = txs.where((t) => t.id != id).toList();
    notifyListeners();
    await updateHomeWidget();
    if (_cloudOn) {
      final ok = await _tryDeleteTxCloud(id);
      if (!ok) _enqueue(_QueuedOp(table: 'transactions', op: 'delete', id: id));
    }
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
    if (_cloudOn) {
      final ok = await _tryPushCustomerCloud(saved);
      if (!ok) _enqueue(_QueuedOp(table: 'customers', op: 'upsert', data: saved.toMap()));
    }
    return saved;
  }

  Future<void> deleteCustomer(int id) async {
    await DbService.deleteCustomer(id);
    customers = customers.where((c) => c.id != id).toList();
    notifyListeners();
    if (_cloudOn) {
      final ok = await _tryDeleteCustomerCloud(id);
      if (!ok) _enqueue(_QueuedOp(table: 'customers', op: 'delete', id: id));
    }
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
    if (_cloudOn) {
      final ok = await _tryPushEmployeeCloud(saved);
      if (!ok) _enqueue(_QueuedOp(table: 'employees', op: 'upsert', data: saved.toMap()));
    }
    return saved;
  }

  Future<void> deleteEmployee(int id) async {
    await DbService.deleteEmployee(id);
    employees = employees.where((e) => e.id != id).toList();
    notifyListeners();
    if (_cloudOn) {
      final ok = await _tryDeleteEmployeeCloud(id);
      if (!ok) _enqueue(_QueuedOp(table: 'employees', op: 'delete', id: id));
    }
  }

  // ── Invoice save ─────────────────────────────────────────────────────────────
  Future<void> saveInvoice({
    required String invNo, required String invDate, required String dueDate,
    required Customer customer, required List<Map<String, String>> items,
    required String notes, required String terms,
    required String bankName, required String bankAcct,
    String? logoB64, String? sigB64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.invoices) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final record = {
      'invNo': invNo, 'invDate': invDate, 'dueDate': dueDate,
      'customer': customer.toMap(), 'items': items,
      'notes': notes, 'terms': terms, 'bankName': bankName, 'bankAcct': bankAcct,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['invNo'] == invNo);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.invoices, jsonEncode(list));
    if (_cloudOn) _pushInvoicesCloud(list);
  }

  // ── Payroll save ─────────────────────────────────────────────────────────────
  Future<void> savePayroll({
    required Employee emp, required int month, required int year,
    required List<Map<String, String>> earnings,
    required List<Map<String, String>> deductions,
    required bool useEPF, required bool useSOCSO, required bool useEIS,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.payrolls) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final key = '${emp.id}_${year}_$month';
    final record = {
      'key': key, 'empId': emp.id, 'empName': emp.name,
      'month': month, 'year': year,
      'earnings': earnings, 'deductions': deductions,
      'useEPF': useEPF, 'useSOCSO': useSOCSO, 'useEIS': useEIS,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['key'] == key);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.payrolls, jsonEncode(list));
    if (_cloudOn) _pushPayrollsCloud(list);
  }

  // ── Cloud pull ───────────────────────────────────────────────────────────────
  Future<bool> pullCloud() async {
    if (!_cloudOn) return true; // non-default companies are device-local
    syncStatus = SyncStatus.pulling; syncError = null;
    notifyListeners();
    try {
      final uid = _uid!;

      // ── Transactions ──────────────────────────────────────────────────────
      final remoteTxs = await SupabaseService.loadTxs();
      final remoteMap = {for (final tx in remoteTxs) tx.id: tx};
      final localMap  = {for (final tx in txs) tx.id: tx};
      final merged = <Transaction>[];
      final allIds = {...remoteMap.keys, ...localMap.keys};
      for (final id in allIds) {
        final r = remoteMap[id];
        final l = localMap[id];
        if (r == null) {
          // 本地有，云端没有 → 推上云，保留本地版本
          merged.add(l!);
          _pushTxCloud(l);
        } else {
          // 云端有 → 云端为准，写回本地 SQLite
          merged.add(r);
          await DbService.upsertTx(r);
        }
      }
      merged.sort((a, b) => b.date.compareTo(a.date));
      txs = merged;

      // ── Customers ─────────────────────────────────────────────────────────
      final remoteCusts = await _sb.from('customers').select().eq('user_id', uid).eq('company_id', activeCompany);
      // 合并：云端有的写回本地；本地有云端没有的推上云
      final remoteCustomerIds = <int>{};
      for (final row in (remoteCusts as List)) {
        final c = Customer.fromMap(row);
        remoteCustomerIds.add(c.id);
        await DbService.upsertCustomer(c);
      }
      for (final c in customers) {
        if (!remoteCustomerIds.contains(c.id)) _pushCustomerCloud(c);
      }
      customers = await DbService.loadCustomers();

      // ── Employees ─────────────────────────────────────────────────────────
      final remoteEmps = await _sb.from('employees').select().eq('user_id', uid).eq('company_id', activeCompany);
      final remoteEmpIds = <int>{};
      for (final row in (remoteEmps as List)) {
        final e = Employee.fromMap(row);
        remoteEmpIds.add(e.id);
        await DbService.upsertEmployee(e);
      }
      for (final e in employees) {
        if (!remoteEmpIds.contains(e.id)) _pushEmployeeCloud(e);
      }
      employees = await DbService.loadEmployees();

      // ── Invoices / Payrolls ───────────────────────────────────────────────
      final invRow = await _sb.from('user_data').select('invoices').eq('user_id', uid).eq('company_id', activeCompany).maybeSingle();
      if (invRow != null && invRow['invoices'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.invoices, jsonEncode(invRow['invoices']));
      }

      final payRow = await _sb.from('user_data').select('payrolls').eq('user_id', uid).eq('company_id', activeCompany).maybeSingle();
      if (payRow != null && payRow['payrolls'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.payrolls, jsonEncode(payRow['payrolls']));
      }

      // ── Settings ──────────────────────────────────────────────────────────
      final remoteS = await SupabaseService.loadSettings();
      // Keep dark mode (device-local) — the cloud map doesn't carry it.
      if (remoteS != null) settings = AppSettings.fromMap(remoteS).copyWith(dark: settings.dark);

      syncStatus = SyncStatus.done;
      notifyListeners();
      await updateHomeWidget();
      return true;
    } catch (e) {
      // FIX: 拉取失败时不改动 txs/customers/employees，保留现有本地数据
      syncStatus = SyncStatus.error;
      syncError  = e.toString().substring(0, 60.clamp(0, e.toString().length));
      notifyListeners();
      return false;
    }
  }

  Future<bool> pushCloud() async {
    if (!_cloudOn) return true; // non-default companies are device-local
    syncStatus = SyncStatus.pushing; syncError = null;
    notifyListeners();
    try {
      await SupabaseService.upsertTxs(txs);
      await SupabaseService.saveSettings(settings.toMap());
      if (_uid != null) {
        for (final c in customers) { await _pushCustomerCloud(c); }
        for (final e in employees) { await _pushEmployeeCloud(e); }
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

  // ── Offline queue ─────────────────────────────────────────────────────────────
  void _enqueue(_QueuedOp op) async {
    _queue.add(op);
    pendingOps = _queue.length;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.offlineQueue,
        jsonEncode(_queue.map((e) => e.toMap()).toList()));
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty) return;
    final failed = <_QueuedOp>[];
    for (final op in List.from(_queue)) {
      bool ok = false;
      try {
        if (op.op == 'upsert' && op.data != null) {
          await _sb.from(op.table).upsert({
            ...op.data!, 'user_id': _uid, 'company_id': op.companyId,
            'updated_at': DateTime.now().toIso8601String(),
          }, onConflict: 'id,user_id,company_id');
          ok = true;
        } else if (op.op == 'delete' && op.id != null) {
          await _sb.from(op.table).delete()
              .eq('id', op.id!).eq('user_id', _uid!).eq('company_id', op.companyId);
          ok = true;
        }
      } catch (_) {}
      if (!ok) failed.add(op);
    }
    _queue..clear()..addAll(failed);
    pendingOps = _queue.length;
    final prefs = await SharedPreferences.getInstance();
    if (_queue.isEmpty) {
      await prefs.remove(StorageKeys.offlineQueue);
    } else {
      await prefs.setString(StorageKeys.offlineQueue,
          jsonEncode(_queue.map((e) => e.toMap()).toList()));
    }
    notifyListeners();
  }

  Future<void> onReconnect() async {
    isOnline = true;
    notifyListeners();
    if (_cloudOn) { await _flushQueue(); await pullCloud(); }
  }

  // ── Try-push helpers ──────────────────────────────────────────────────────────
  // Every cloud row carries company_id so companies stay isolated (Phase 4 #24).
  Future<bool> _tryPushTxCloud(Transaction tx) async {
    try {
      await _sb.from('transactions').upsert({...tx.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id');
      return true;
    } catch (_) { return false; }
  }
  Future<bool> _tryDeleteTxCloud(int id) async {
    try { await _sb.from('transactions').delete().eq('id', id).eq('user_id', _uid!).eq('company_id', activeCompany); return true; } catch (_) { return false; }
  }
  Future<bool> _tryPushCustomerCloud(Customer c) async {
    try {
      await _sb.from('customers').upsert({...c.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id');
      return true;
    } catch (_) { return false; }
  }
  Future<bool> _tryDeleteCustomerCloud(int id) async {
    try { await _sb.from('customers').delete().eq('id', id).eq('user_id', _uid!).eq('company_id', activeCompany); return true; } catch (_) { return false; }
  }
  Future<bool> _tryPushEmployeeCloud(Employee e) async {
    try {
      await _sb.from('employees').upsert({...e.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id');
      return true;
    } catch (_) { return false; }
  }
  Future<bool> _tryDeleteEmployeeCloud(int id) async {
    try { await _sb.from('employees').delete().eq('id', id).eq('user_id', _uid!).eq('company_id', activeCompany); return true; } catch (_) { return false; }
  }

  // ── Fire-and-forget helpers ───────────────────────────────────────────────────
  Future<void> _pushTxCloud(Transaction tx) async {
    try { await _sb.from('transactions').upsert({...tx.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id'); } catch (_) {}
  }
  Future<void> _pushCustomerCloud(Customer c) async {
    try { await _sb.from('customers').upsert({...c.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id'); } catch (_) {}
  }
  Future<void> _pushEmployeeCloud(Employee e) async {
    try { await _sb.from('employees').upsert({...e.toMap(), 'user_id': _uid, 'company_id': activeCompany, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'id,user_id,company_id'); } catch (_) {}
  }
  Future<void> _pushInvoicesCloud(List list) async {
    try { await _sb.from('user_data').upsert({'user_id': _uid, 'company_id': activeCompany, 'invoices': list, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'user_id,company_id'); } catch (_) {}
  }
  Future<void> _pushPayrollsCloud(List list) async {
    try { await _sb.from('user_data').upsert({'user_id': _uid, 'company_id': activeCompany, 'payrolls': list, 'updated_at': DateTime.now().toIso8601String()}, onConflict: 'user_id,company_id'); } catch (_) {}
  }
  Future<void> _pushSettingsCloud() async {
    try { await SupabaseService.saveSettings(settings.toMap()); } catch (_) {}
  }

  // ── Home-screen widget (Phase 4 #26) ───────────────────────────────────────
  /// Push the active company's CURRENT-MONTH summary to the Android widget.
  /// Uses the real calendar month (independent of the UI date-range filter) so
  /// the "This month" label is always accurate.
  Future<void> updateHomeWidget() async {
    final cm = currentMonth; // yyyy-MM
    double income = 0, expense = 0;
    for (final t in txs) {
      if (!t.date.startsWith(cm)) continue;
      if (t.type == 'income') {
        income += t.amountMYR;
      } else if (t.type == 'expense') {
        expense += t.amountMYR;
      }
    }
    final net  = income - expense;
    final lang = settings.lang;
    await WidgetService.update(
      company:    activeCompanyObj.name,
      net:        '${net >= 0 ? '+' : '-'}${fmtShort(net.abs())}',
      income:     fmtShort(income),
      expense:    fmtShort(expense),
      lblNet:     tr(lang, 'This month', '本月净利', 'Bulan ini'),
      lblIncome:  tr(lang, 'Income', '收入', 'Masuk'),
      lblExpense: tr(lang, 'Expense', '支出', 'Keluar'),
      btnIncome:  tr(lang, '+ Income', '+ 收入', '+ Masuk'),
      btnExpense: tr(lang, '+ Expense', '+ 支出', '+ Keluar'),
    );
  }

  // ── Ledger ────────────────────────────────────────────────────────────────────
  Map<String, double> computeBalances([List<Transaction>? source]) {
    final list = source ?? txs;
    final b = <String, double>{for (final k in accounts.keys) k: 0.0};
    for (final tx in list) {
      for (final e in tx.entries) {
        final acc = accounts[e.acc]; if (acc == null) continue;
        final dr = acc.normal == 'Dr';
        b[e.acc] = (b[e.acc] ?? 0) + (dr ? (e.dc=='Dr'?e.val:-e.val) : (e.dc=='Cr'?e.val:-e.val));
      }
    }
    return b;
  }

  // ── Date range filter (Task 3: custom date range) ────────────────────────────
  DateTime? filterFrom;
  DateTime? filterTo;

  void setDateRange(DateTime? from, DateTime? to) {
    filterFrom = from;
    filterTo   = to;
    notifyListeners();
  }

  void clearDateRange() {
    filterFrom = null;
    filterTo   = null;
    notifyListeners();
  }

  bool get hasCustomRange => filterFrom != null && filterTo != null;

  String get currentMonth => DateTime.now().toIso8601String().substring(0, 7);

  String get dateRangeLabel {
    if (hasCustomRange) {
      final f = filterFrom!; final t = filterTo!;
      return '${f.day}/${f.month}/${f.year} – ${t.day}/${t.month}/${t.year}';
    }
    return currentMonth;
  }

  List<Transaction> get thisMonthTxs {
    if (hasCustomRange) {
      final fromStr = filterFrom!.toIso8601String().substring(0, 10);
      final toStr   = filterTo!.toIso8601String().substring(0, 10);
      return txs.where((t) => t.date.compareTo(fromStr) >= 0 && t.date.compareTo(toStr) <= 0).toList();
    }
    return txs.where((t) => t.date.startsWith(currentMonth)).toList();
  }

  List<String> get availableMonths => txs.map((t) => t.date.substring(0, 7)).toSet().toList()..sort((a,b)=>b.compareTo(a));

  String? get currentUid => _uid;
  User?   get currentUser => _sb.auth.currentUser;
  
  String _timeStr() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2,'0')}:${n.minute.toString().padLeft(2,'0')}';
  }

  // ── Quotation CRUD ────────────────────────────────────────────────────────────
  Future<void> saveQuotation({
    required String quotNo, required String quotDate, required String validUntil,
    required Customer customer, required List<Map<String, String>> items,
    required String notes, String status = 'draft',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.quotations) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final record = {
      'quotNo': quotNo, 'quotDate': quotDate, 'validUntil': validUntil,
      'customer': customer.toMap(), 'items': items,
      'notes': notes, 'status': status,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['quotNo'] == quotNo);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.quotations, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> loadQuotations() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.quotations) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteQuotation(String quotNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.quotations) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['quotNo'] == quotNo);
    await prefs.setString(StorageKeys.quotations, jsonEncode(list));
  }

  Future<void> markQuotationStatus(String quotNo, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.quotations) ?? '[]') as List).cast<Map<String, dynamic>>();
    final idx = list.indexWhere((e) => e['quotNo'] == quotNo);
    if (idx >= 0) {
      list[idx] = Map<String, dynamic>.from(list[idx])..['status'] = status;
      await prefs.setString(StorageKeys.quotations, jsonEncode(list));
    }
  }

  // ── Delivery Order CRUD ─────────────────────────────────────────────────────
  Future<void> saveDeliveryOrder({
    required String doNo, required String doDate,
    required Customer customer, required List<Map<String, String>> items,
    required String notes, String refInvNo = '', String driver = '',
    String status = 'draft',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.deliveryOrders) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final record = {
      'doNo': doNo, 'doDate': doDate,
      'customer': customer.toMap(), 'items': items,
      'notes': notes, 'refInvNo': refInvNo, 'driver': driver, 'status': status,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['doNo'] == doNo);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.deliveryOrders, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> loadDeliveryOrders() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.deliveryOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteDeliveryOrder(String doNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.deliveryOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['doNo'] == doNo);
    await prefs.setString(StorageKeys.deliveryOrders, jsonEncode(list));
  }

  Future<void> markDeliveryOrderStatus(String doNo, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.deliveryOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
    final idx = list.indexWhere((e) => e['doNo'] == doNo);
    if (idx >= 0) {
      list[idx] = Map<String, dynamic>.from(list[idx])..['status'] = status;
      await prefs.setString(StorageKeys.deliveryOrders, jsonEncode(list));
    }
  }

  // ── Credit Note CRUD (document storage; AR posting done in AccountingState) ──
  Future<void> saveCreditNote({
    required String cnNo, required String cnDate,
    required Customer customer, required List<Map<String, String>> items,
    required String notes, required String reason,
    String refInvNo = '', String status = 'draft',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.creditNotes) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final record = {
      'cnNo': cnNo, 'cnDate': cnDate,
      'customer': customer.toMap(), 'items': items,
      'notes': notes, 'reason': reason, 'refInvNo': refInvNo, 'status': status,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['cnNo'] == cnNo);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.creditNotes, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> loadCreditNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.creditNotes) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteCreditNote(String cnNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.creditNotes) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['cnNo'] == cnNo);
    await prefs.setString(StorageKeys.creditNotes, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> loadInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.invoices) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteInvoice(String invNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.invoices) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['invNo'] == invNo);
    await prefs.setString(StorageKeys.invoices, jsonEncode(list));
    if (_cloudOn) _pushInvoicesCloud(list);
  }

  Future<List<Map<String, dynamic>>> loadPayrolls() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.payrolls) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deletePayroll(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.payrolls) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['key'] == key);
    await prefs.setString(StorageKeys.payrolls, jsonEncode(list));
    if (_cloudOn) _pushPayrollsCloud(list);
  }

  // ── Warehouses / stores (Phase 4 #25) ─────────────────────────────────────────
  // Self-contained local store so the synced inventory model is untouched.
  // Shape: { "list": [ {id, name} ], "assign": { "<itemId>": <warehouseId> } }
  Future<Map<String, dynamic>> loadWarehouseStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.warehouses);
    if (raw == null) return {'list': <dynamic>[], 'assign': <String, dynamic>{}};
    final m = Map<String, dynamic>.from(jsonDecode(raw));
    m['list']   = (m['list'] as List? ?? []);
    m['assign'] = Map<String, dynamic>.from(m['assign'] ?? {});
    return m;
  }

  Future<void> saveWarehouseStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.warehouses, jsonEncode(store));
  }

  // ── Budgets (Phase 4 #20): { catId: monthlyLimit } ────────────────────────────
  Future<Map<String, double>> loadBudgets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.budgets);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
  }

  Future<void> saveBudgets(Map<String, double> budgets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.budgets, jsonEncode(budgets));
  }

  // ── Recurring transactions (Phase 4 #21) ──────────────────────────────────────
  // Template: { id, type, catId, amount, descEN, descZH, freq(monthly|weekly),
  //             anchorDay, nextDate(yyyy-MM-dd), active }
  Future<List<Map<String, dynamic>>> loadRecurring() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.recurring) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveRecurringList(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.recurring, jsonEncode(list));
  }

  Future<void> saveRecurring(Map<String, dynamic> tpl) async {
    final list = await loadRecurring();
    final idx = list.indexWhere((e) => e['id'] == tpl['id']);
    if (idx >= 0) { list[idx] = tpl; } else { list.insert(0, tpl); }
    await saveRecurringList(list);
  }

  Future<void> deleteRecurring(int id) async {
    final list = await loadRecurring();
    list.removeWhere((e) => e['id'] == id);
    await saveRecurringList(list);
  }

  /// Generate any due recurring transactions (catch-up) and advance nextDate.
  /// Deterministic per-occurrence ids → safe to run on every launch.
  Future<int> processRecurring() async {
    final list = await loadRecurring();
    if (list.isEmpty) return 0;
    final today = DateTime.now();
    int generated = 0;
    var changed = false;

    for (final tpl in list) {
      if (tpl['active'] == false) continue;
      final catId = tpl['catId'] as String? ?? '';
      final cat = findCat(catId);
      if (cat == null) continue;
      final amount = (tpl['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;

      var next = DateTime.tryParse(tpl['nextDate'] as String? ?? '');
      if (next == null) continue;
      final freq    = tpl['freq'] as String? ?? 'monthly';
      final anchor  = (tpl['anchorDay'] as int?) ?? next.day;

      while (!next!.isAfter(today)) {
        final dateStr = next.toIso8601String().substring(0, 10);
        final occId = (tpl['id'] as int) * 100000000 +
            int.parse(dateStr.replaceAll('-', ''));
        await addOrUpdateTx(Transaction(
          id:           occId,
          type:         tpl['type'] as String? ?? 'expense',
          catId:        catId,
          amountMYR:    amount,
          origAmount:   amount,
          origCurrency: 'MYR',
          sstKey:       'none',
          sstMYR:       0,
          descEN:       '${tpl['descEN'] ?? cat.enLabel} (auto)',
          descZH:       '${tpl['descZH'] ?? cat.zhLabel} (自动)',
          date:         dateStr,
          entries:      cat.mkEntries(amount),
        ));
        generated++;
        changed = true;
        // advance
        next = freq == 'weekly'
            ? next.add(const Duration(days: 7))
            : _addMonthClamped(next, anchor);
      }
      tpl['nextDate'] = next.toIso8601String().substring(0, 10);
    }
    if (changed) await saveRecurringList(list);
    return generated;
  }

  static DateTime _addMonthClamped(DateTime d, int anchorDay) {
    final y = d.month == 12 ? d.year + 1 : d.year;
    final m = d.month == 12 ? 1 : d.month + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, anchorDay.clamp(1, lastDay));
  }

  // ── Purchase Order CRUD (Phase 3 Task #18) ────────────────────────────────────
  Future<void> savePurchaseOrder({
    required String poNo, required String poDate,
    required Map<String, dynamic> supplier,
    required List<Map<String, String>> items,
    required String notes, String status = 'ordered',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list  = (jsonDecode(prefs.getString(StorageKeys.purchaseOrders) ?? '[]') as List)
        .cast<Map<String, dynamic>>();
    final record = {
      'poNo': poNo, 'poDate': poDate, 'supplier': supplier, 'items': items,
      'notes': notes, 'status': status, 'savedAt': DateTime.now().toIso8601String(),
    };
    final idx = list.indexWhere((e) => e['poNo'] == poNo);
    if (idx >= 0) { list[idx] = record; } else { list.insert(0, record); }
    await prefs.setString(StorageKeys.purchaseOrders, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> loadPurchaseOrders() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString(StorageKeys.purchaseOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
  }

  Future<void> deletePurchaseOrder(String poNo) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.purchaseOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
    list.removeWhere((e) => e['poNo'] == poNo);
    await prefs.setString(StorageKeys.purchaseOrders, jsonEncode(list));
  }

  Future<void> markPurchaseOrderStatus(String poNo, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final list = (jsonDecode(prefs.getString(StorageKeys.purchaseOrders) ?? '[]') as List).cast<Map<String, dynamic>>();
    final idx = list.indexWhere((e) => e['poNo'] == poNo);
    if (idx >= 0) {
      list[idx] = Map<String, dynamic>.from(list[idx])..['status'] = status;
      await prefs.setString(StorageKeys.purchaseOrders, jsonEncode(list));
    }
  }

  // ── Leave store (Phase 3 Task #14) ────────────────────────────────────────────
  // Self-contained local store so we don't touch the Employee schema / cloud sync.
  // Shape: { "hireDates": { "<empId>": "yyyy-MM-dd" }, "records": [ {...} ] }
  Future<Map<String, dynamic>> loadLeaveStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.leave);
    if (raw == null) return {'hireDates': <String, dynamic>{}, 'records': <dynamic>[]};
    final m = Map<String, dynamic>.from(jsonDecode(raw));
    m['hireDates'] = Map<String, dynamic>.from(m['hireDates'] ?? {});
    m['records']   = (m['records'] as List? ?? []);
    return m;
  }

  Future<void> saveLeaveStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.leave, jsonEncode(store));
  }
}
