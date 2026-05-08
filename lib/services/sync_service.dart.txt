import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'db_service.dart';

/// Syncs local SQLite data ↔ Supabase cloud.
/// Call [SyncService.syncAll()] after login and after any local write.
class SyncService {
  static final _sb = Supabase.instance.client;

  static String? get _uid => _sb.auth.currentUser?.id;

  // ── Public entry point ────────────────────────────────────────────────────

  /// Upload local data to cloud, then pull any cloud data not in local.
  static Future<void> syncAll() async {
    final uid = _uid;
    if (uid == null) return; // not logged in, skip

    await _syncTransactions(uid);
    await _syncCustomers(uid);
    await _syncEmployees(uid);
    await _syncInvoiceSeq(uid);
  }

  // ── Transactions ──────────────────────────────────────────────────────────

  static Future<void> _syncTransactions(String uid) async {
    final localTxs = await DbService.loadTxs();

    // Upload all local rows (upsert by id + user_id)
    if (localTxs.isNotEmpty) {
      final rows = localTxs.map((tx) => {
        ...tx.toMap(),
        'user_id': uid,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();

      await _sb.from('transactions').upsert(rows, onConflict: 'id,user_id');
    }

    // Pull cloud rows not in local
    final localIds = localTxs.map((t) => t.id).toSet();
    final remote = await _sb
        .from('transactions')
        .select()
        .eq('user_id', uid);

    for (final row in remote as List) {
      final id = row['id'] as int;
      if (!localIds.contains(id)) {
        await DbService.upsertTx(Transaction.fromMap(row));
      }
    }
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  static Future<void> _syncCustomers(String uid) async {
    final localList = await DbService.loadCustomers();

    if (localList.isNotEmpty) {
      final rows = localList.map((c) => {
        ...c.toMap(),
        'user_id': uid,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();

      await _sb.from('customers').upsert(rows, onConflict: 'id,user_id');
    }

    final localIds = localList.map((c) => c.id).toSet();
    final remote = await _sb
        .from('customers')
        .select()
        .eq('user_id', uid);

    for (final row in remote as List) {
      final id = row['id'] as int;
      if (!localIds.contains(id)) {
        await DbService.upsertCustomer(Customer.fromMap(row));
      }
    }
  }

  // ── Employees ─────────────────────────────────────────────────────────────

  static Future<void> _syncEmployees(String uid) async {
    final localList = await DbService.loadEmployees();

    if (localList.isNotEmpty) {
      final rows = localList.map((e) => {
        ...e.toMap(),
        'user_id': uid,
        'updated_at': DateTime.now().toIso8601String(),
      }).toList();

      await _sb.from('employees').upsert(rows, onConflict: 'id,user_id');
    }

    final localIds = localList.map((e) => e.id).toSet();
    final remote = await _sb
        .from('employees')
        .select()
        .eq('user_id', uid);

    for (final row in remote as List) {
      final id = row['id'] as int;
      if (!localIds.contains(id)) {
        await DbService.upsertEmployee(Employee.fromMap(row));
      }
    }
  }

  // ── Invoice Seq ───────────────────────────────────────────────────────────

  static Future<void> _syncInvoiceSeq(String uid) async {
    final d    = await DbService.db;
    final year = DateTime.now().year;
    final local = await d.query('invoice_seq',
        where: 'year = ?', whereArgs: [year]);

    final localSeq = local.isNotEmpty
        ? (local.first['last_seq'] as int? ?? 0)
        : 0;

    // Get cloud seq
    final remote = await _sb
        .from('invoice_seq')
        .select()
        .eq('user_id', uid)
        .eq('year', year)
        .maybeSingle();

    final cloudSeq = remote != null
        ? (remote['last_seq'] as int? ?? 0)
        : 0;

    // Take the higher value (never go backwards)
    final maxSeq = localSeq > cloudSeq ? localSeq : cloudSeq;

    // Update cloud
    await _sb.from('invoice_seq').upsert({
      'user_id': uid,
      'year': year,
      'last_seq': maxSeq,
    }, onConflict: 'user_id,year');

    // Update local
    await d.execute(
      'INSERT OR REPLACE INTO invoice_seq(year, last_seq) VALUES(?, ?)',
      [year, maxSeq],
    );
  }

  // ── Helpers for write-through (call after local save) ────────────────────

  /// Call after upsertTx() to immediately push to cloud
  static Future<void> pushTx(Transaction tx) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('transactions').upsert({
      ...tx.toMap(),
      'user_id': uid,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id,user_id');
  }

  /// Call after deleteTx() to immediately delete from cloud
  static Future<void> deleteTxCloud(int id) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('transactions')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
  }

  /// Call after upsertCustomer()
  static Future<void> pushCustomer(Customer c) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('customers').upsert({
      ...c.toMap(),
      'user_id': uid,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id,user_id');
  }

  /// Call after deleteCustomer()
  static Future<void> deleteCustomerCloud(int id) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('customers')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
  }

  /// Call after upsertEmployee()
  static Future<void> pushEmployee(Employee e) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('employees').upsert({
      ...e.toMap(),
      'user_id': uid,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'id,user_id');
  }

  /// Call after deleteEmployee()
  static Future<void> deleteEmployeeCloud(int id) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('employees')
        .delete()
        .eq('id', id)
        .eq('user_id', uid);
  }
}
