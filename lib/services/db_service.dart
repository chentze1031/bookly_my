// ignore: depend_on_referenced_packages
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';
import '../models.dart';

class DbService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'bookly.db');
    return openDatabase(path, version: 2, onCreate: (db, v) async {
      await db.execute('''CREATE TABLE transactions(
        id INTEGER PRIMARY KEY, type TEXT, cat_id TEXT,
        amount_myr REAL, orig_amount REAL, orig_currency TEXT,
        sst_key TEXT, sst_myr REAL,
        desc_en TEXT, desc_zh TEXT, date TEXT, entries TEXT
      )''');
      await db.execute('''CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, reg_no TEXT, sst_reg_no TEXT,
        address TEXT, phone TEXT, email TEXT
      )''');
      await db.execute('''CREATE TABLE employees(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, ic_no TEXT, position TEXT, department TEXT,
        basic_salary REAL, epf_no TEXT, socso_no TEXT,
        bank_name TEXT, bank_acct TEXT, phone TEXT, email TEXT
      )''');
      // Invoice sequence counter — one row per year
      await db.execute('''CREATE TABLE invoice_seq(
        year INTEGER PRIMARY KEY,
        last_seq INTEGER NOT NULL DEFAULT 0
      )''');
    }, onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) {
        await db.execute('''CREATE TABLE IF NOT EXISTS invoice_seq(
          year INTEGER PRIMARY KEY,
          last_seq INTEGER NOT NULL DEFAULT 0
        )''');
      }
    });
  }

  // ── Invoice sequence ───────────────────────────────────────────────────────
  // Returns the next invoice number string, e.g. "INV-2026-0042"
  // Atomically increments the counter in the DB so every call is unique.
  static Future<String> nextInvoiceNo() async {
    final d    = await db;
    final year = DateTime.now().year;
    // Insert year row if it doesn't exist yet
    await d.execute(
      'INSERT OR IGNORE INTO invoice_seq(year, last_seq) VALUES(?, 0)',
      [year],
    );
    // Increment atomically
    await d.execute(
      'UPDATE invoice_seq SET last_seq = last_seq + 1 WHERE year = ?',
      [year],
    );
    final rows = await d.query('invoice_seq', where: 'year = ?', whereArgs: [year]);
    final seq  = (rows.first['last_seq'] as int?) ?? 1;
    return 'INV-$year-${seq.toString().padLeft(4, '0')}';
  }

  static Future<List<Transaction>> loadTxs() async {
    final d = await db;
    final rows = await d.query('transactions', orderBy: 'date DESC');
    return rows.map(Transaction.fromMap).toList();
  }

  static Future<void> upsertTx(Transaction tx) async {
    final d = await db;
    await d.insert('transactions', tx.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> deleteTx(int id) async {
    final d = await db;
    await d.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> clearTxs() async {
    final d = await db;
    await d.delete('transactions');
  }

  static Future<List<Customer>> loadCustomers() async {
    final d = await db;
    final rows = await d.query('customers', orderBy: 'name ASC');
    return rows.map(Customer.fromMap).toList();
  }

  static Future<Customer> upsertCustomer(Customer c) async {
    final d = await db;
    if (c.id == 0) {
      final map = Map<String, dynamic>.from(c.toMap())..remove('id');
      final id = await d.insert('customers', map);
      return c.copyWith(id: id);
    }
    await d.update('customers', c.toMap(),
        where: 'id = ?', whereArgs: [c.id]);
    return c;
  }

  static Future<void> deleteCustomer(int id) async {
    final d = await db;
    await d.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Employee>> loadEmployees() async {
    final d = await db;
    final rows = await d.query('employees', orderBy: 'name ASC');
    return rows.map(Employee.fromMap).toList();
  }

  static Future<Employee> upsertEmployee(Employee e) async {
    final d = await db;
    if (e.id == 0) {
      final map = Map<String, dynamic>.from(e.toMap())..remove('id');
      final id = await d.insert('employees', map);
      return e.copyWith(id: id);
    }
    await d.update('employees', e.toMap(),
        where: 'id = ?', whereArgs: [e.id]);
    return e;
  }

  static Future<void> deleteEmployee(int id) async {
    final d = await db;
    await d.delete('employees', where: 'id = ?', whereArgs: [id]);
  }
}
