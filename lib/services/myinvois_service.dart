import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'myinvois_ubl.dart';

/// Result of a MyInvois submit / status call.
class MyInvoisResult {
  final bool ok;
  final String? submissionUid;
  final String? uuid;
  final String? longId;
  final String status; // none | InProgress | Valid | Invalid | error
  final String? error;
  const MyInvoisResult({
    required this.ok,
    this.submissionUid,
    this.uuid,
    this.longId,
    this.status = 'none',
    this.error,
  });
}

/// Talks to the `myinvois` Edge Function (Phase 4 #28). Credentials live in the
/// cloud `myinvois_credentials` table (RLS); this never holds the secret.
class MyInvoisService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static bool get isLoggedIn => _sb.auth.currentUser != null;

  // ── Credentials (stored server-side, RLS-scoped to the user) ───────────────
  static Future<Map<String, dynamic>?> loadCredentials() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    return await _sb
        .from('myinvois_credentials')
        .select('client_id, env')
        .eq('user_id', uid)
        .maybeSingle();
  }

  static Future<void> saveCredentials({
    required String clientId,
    required String clientSecret,
    required String env,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not signed in');
    final row = <String, dynamic>{
      'user_id': uid,
      'client_id': clientId.trim(),
      'env': env,
      'updated_at': DateTime.now().toIso8601String(),
    };
    // Only overwrite the secret when a new one was entered (keep existing else).
    if (clientSecret.trim().isNotEmpty) row['client_secret'] = clientSecret.trim();
    await _sb.from('myinvois_credentials').upsert(row, onConflict: 'user_id');
  }

  // ── Submit an invoice ──────────────────────────────────────────────────────
  static Future<MyInvoisResult> submitInvoice({
    required Map<String, dynamic> invoice,
    required AppSettings supplier,
    required Customer buyer,
  }) async {
    if (!isLoggedIn) {
      return const MyInvoisResult(ok: false, status: 'error', error: 'Sign in required');
    }
    final doc = MyInvoisUbl.buildInvoice(inv: invoice, s: supplier, buyer: buyer);
    try {
      final res = await _sb.functions.invoke('myinvois', body: {
        'action': 'submit',
        'document': doc,
        'codeNumber': invoice['invNo'] ?? '',
      });
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) {
        return MyInvoisResult(
          ok: false, status: 'error',
          error: _err(data) ?? 'Submit failed (${res.status})',
        );
      }
      final inner = data['data'] as Map<String, dynamic>? ?? {};
      final accepted = (inner['acceptedDocuments'] as List?) ?? [];
      final rejected = (inner['rejectedDocuments'] as List?) ?? [];
      if (rejected.isNotEmpty) {
        return MyInvoisResult(
          ok: false, status: 'Invalid',
          error: rejected.first.toString(),
          submissionUid: inner['submissionUid'] as String?,
        );
      }
      return MyInvoisResult(
        ok: true,
        status: 'InProgress',
        submissionUid: inner['submissionUid'] as String?,
        uuid: accepted.isNotEmpty ? accepted.first['uuid'] as String? : null,
      );
    } catch (e) {
      return MyInvoisResult(ok: false, status: 'error', error: e.toString());
    }
  }

  // ── Poll submission status ─────────────────────────────────────────────────
  static Future<MyInvoisResult> checkStatus(String submissionUid) async {
    try {
      final res = await _sb.functions.invoke('myinvois', body: {
        'action': 'status',
        'submissionUid': submissionUid,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) {
        return MyInvoisResult(
          ok: false, status: 'error', submissionUid: submissionUid,
          error: _err(data) ?? 'Status check failed (${res.status})',
        );
      }
      final inner = data['data'] as Map<String, dynamic>? ?? {};
      final summary = (inner['documentSummary'] as List?) ?? [];
      final doc = summary.isNotEmpty ? summary.first as Map<String, dynamic> : null;
      final overall = (inner['overallStatus'] ?? doc?['status'] ?? 'InProgress').toString();
      return MyInvoisResult(
        ok: true,
        status: overall,
        submissionUid: submissionUid,
        uuid: doc?['uuid'] as String?,
        longId: doc?['longId'] as String?,
      );
    } catch (e) {
      return MyInvoisResult(ok: false, status: 'error', error: e.toString());
    }
  }

  static String? _err(Map<String, dynamic>? data) {
    if (data == null) return null;
    if (data['error'] != null) return data['error'].toString();
    final inner = data['data'];
    if (inner is Map && inner['error'] != null) return inner['error'].toString();
    return null;
  }

  /// Public portal validation URL for a validated document's QR code.
  static String validationUrl(String env, String uuid, String longId) {
    final portal = env == 'prod'
        ? 'https://myinvois.hasil.gov.my'
        : 'https://preprod.myinvois.hasil.gov.my';
    return '$portal/$uuid/share/$longId';
  }
}
