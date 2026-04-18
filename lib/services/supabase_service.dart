import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class SupabaseService {
  static const _url = 'https://vzaqoyitschniefmlazi.supabase.co';
  static const _key = 'sb_publishable_UODpeWUIWsQqN5BZHWiH2Q_wjDfTrk-';

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, anonKey: _key);
  }

  // ── Transactions ────────────────────────────────────────────────────────────
  static Map<String, dynamic> txToRow(Transaction tx) => {
    'id':            tx.id,
    'type':          tx.type,
    'cat_id':        tx.catId,
    'amount_myr':    tx.amountMYR,
    'orig_amount':   tx.origAmount,
    'orig_currency': tx.origCurrency,
    'sst_key':       tx.sstKey,
    'sst_myr':       tx.sstMYR,
    'desc_en':       tx.descEN,
    'desc_zh':       tx.descZH,
    'date':          tx.date,
    'entries':       jsonEncode(tx.entries.map((e) => e.toMap()).toList()),
  };

  static Transaction rowToTx(Map<String, dynamic> r) => Transaction.fromMap({
    ...r,
    'id':         r['id'],
    'cat_id':     r['cat_id'],
    'amount_myr': r['amount_myr'],
    'orig_amount':r['orig_amount'],
    'orig_currency':r['orig_currency'],
    'sst_key':    r['sst_key'],
    'sst_myr':    r['sst_myr'],
    'desc_en':    r['desc_en'],
    'desc_zh':    r['desc_zh'],
  });

  static Future<void> upsertTxs(List<Transaction> txs) async {
    if (txs.isEmpty) return;
    await _client.from('transactions').upsert(
      txs.map(txToRow).toList(),
      onConflict: 'id',
    );
  }

  static Future<List<Transaction>> loadTxs() async {
    final rows = await _client
      .from('transactions')
      .select()
      .order('date', ascending: false);
    return (rows as List).map((r) => rowToTx(r as Map<String, dynamic>)).toList();
  }

  static Future<void> saveSettings(Map<String, dynamic> data) async {
    await _client.from('settings').upsert({'id': 1, 'data': jsonEncode(data)});
  }

  static Future<Map<String, dynamic>?> loadSettings() async {
    final rows = await _client.from('settings').select('data').eq('id', 1);
    final list = rows as List;
    if (list.isEmpty) return null;
    final raw = list.first['data'];
    if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
    return raw as Map<String, dynamic>?;
  }
}
