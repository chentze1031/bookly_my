import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

class SupabaseService {
  static const _url = 'https://dgquwkdzmufnrnwquvci.supabase.co';
  static const _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRncXV3a2R6bXVmbnJud3F1dmNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyMjcxMDQsImV4cCI6MjA5NjgwMzEwNH0.GYV7WyfBYLhKk0TpASOP5mff2UnsDkHJm9nAoTwu2Y8';

  static final _sb = Supabase.instance.client;
  static String? get _uid => _sb.auth.currentUser?.id;

  static Future<void> initialize() async {
    await Supabase.initialize(url: _url, publishableKey: _anonKey);
  }

  // ── Transactions ──────────────────────────────────────────────────────────────

  /// Pull all transactions for current user from Supabase.
  static Future<List<Transaction>> loadTxs() async {
    final uid = _uid;
    if (uid == null) return [];
    final rows = await _sb
        .from('transactions')
        .select()
        .eq('user_id', uid);
    return (rows as List)
        .map((r) => Transaction.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Push all local transactions to Supabase (upsert by id + user_id).
  static Future<void> upsertTxs(List<Transaction> txs) async {
    final uid = _uid;
    if (uid == null) return;
    if (txs.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final rows = txs.map((t) => {
      ...t.toMap(),
      'user_id': uid,
      'updated_at': now,
    }).toList();
    await _sb.from('transactions').upsert(rows, onConflict: 'id,user_id');
  }

  // ── Settings ──────────────────────────────────────────────────────────────────

  /// Pull settings for current user from Supabase.
  /// Returns the settings map, or null if not found.
  static Future<Map<String, dynamic>?> loadSettings() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _sb
        .from('user_settings')
        .select('settings')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null || row['settings'] == null) return null;
    return Map<String, dynamic>.from(row['settings'] as Map);
  }

  /// Push settings for current user to Supabase.
  static Future<void> saveSettings(Map<String, dynamic> settingsMap) async {
    final uid = _uid;
    if (uid == null) return;
    await _sb.from('user_settings').upsert({
      'user_id': uid,
      'settings': settingsMap,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
