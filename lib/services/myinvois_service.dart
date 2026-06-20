import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';
import 'cert_service.dart';
import 'myinvois_signer.dart';
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
    final doc = MyInvoisUbl.buildInvoice(
      inv: invoice, s: supplier, buyer: buyer, signed: await _hasCert());
    return _signAndSubmit(doc, (invoice['invNo'] ?? '').toString());
  }

  // ── Submit a B2C consolidated e-Invoice (one doc for many small receipts) ───
  static Future<MyInvoisResult> submitConsolidated({
    required List<Map<String, dynamic>> invoices,
    required AppSettings supplier,
    required String consolidatedInvNo,
  }) async {
    if (!isLoggedIn) {
      return const MyInvoisResult(ok: false, status: 'error', error: 'Sign in required');
    }
    // Flatten every selected invoice's line items, tagging each with its source
    // invoice number so the consolidated doc preserves per-line tax exactly.
    final items = <Map<String, dynamic>>[];
    for (final inv in invoices) {
      final no = (inv['invNo'] ?? '').toString();
      final rows = (inv['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final it in rows) {
        items.add({...it, 'desc': '[$no] ${it['desc'] ?? ''}'.trim()});
      }
    }
    if (items.isEmpty) {
      return const MyInvoisResult(ok: false, status: 'error', error: 'No items to consolidate');
    }
    final consolidatedInv = <String, dynamic>{
      'invNo': consolidatedInvNo,
      'invDate': DateTime.now().toIso8601String().substring(0, 10),
      'items': items,
    };
    final doc = MyInvoisUbl.buildInvoice(
      inv: consolidatedInv, s: supplier,
      buyer: const Customer(id: 0, name: 'General Public'),
      signed: await _hasCert(), consolidated: true);
    return _signAndSubmit(doc, consolidatedInvNo);
  }

  // ── Submit a self-billed e-Invoice (type 11; you issue on supplier's behalf) ─
  static Future<MyInvoisResult> submitSelfBilled({
    required Customer counterparty,
    required Map<String, dynamic> invoice,
    required AppSettings supplier,
    String supplierMsic = '',
    String supplierMsicDesc = '',
  }) async {
    if (!isLoggedIn) {
      return const MyInvoisResult(ok: false, status: 'error', error: 'Sign in required');
    }
    final doc = MyInvoisUbl.buildInvoice(
      inv: invoice, s: supplier, buyer: counterparty,
      signed: await _hasCert(), selfBilledSupplier: counterparty,
      selfBilledMsic: supplierMsic, selfBilledMsicDesc: supplierMsicDesc);
    return _signAndSubmit(doc, (invoice['invNo'] ?? '').toString());
  }

  static Future<bool> _hasCert() async => (await CertService.load()) != null;

  // Sign on-device when a certificate exists (production v1.1), else submit
  // unsigned v1.0 (sandbox only). The private key never leaves the device. The
  // exact serialized bytes we sign are what the Edge Function base64s + hashes,
  // so the submitted document is byte-identical to what was signed.
  static Future<MyInvoisResult> _signAndSubmit(
      Map<String, dynamic> doc, String codeNumber) async {
    final cert = await CertService.load();
    final payload = cert != null ? MyInvoisSigner.sign(doc, cert) : doc;
    final docString = jsonEncode(payload);
    try {
      final res = await _sb.functions.invoke('myinvois', body: {
        'action': 'submit',
        'documentString': docString,
        'codeNumber': codeNumber,
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
        // When Invalid, the Edge Function attaches the LHDN validation reasons.
        error: overall == 'Invalid' ? data['validationError'] as String? : null,
      );
    } catch (e) {
      return MyInvoisResult(ok: false, status: 'error', error: e.toString());
    }
  }

  // ── Cancel a validated document (LHDN allows this within 72h) ──────────────
  static Future<MyInvoisResult> cancelInvoice(String uuid, String reason) async {
    if (!isLoggedIn) {
      return const MyInvoisResult(ok: false, status: 'error', error: 'Sign in required');
    }
    try {
      final res = await _sb.functions.invoke('myinvois', body: {
        'action': 'cancel',
        'uuid': uuid,
        'reason': reason,
      });
      final data = res.data as Map<String, dynamic>?;
      if (data == null || data['ok'] != true) {
        return MyInvoisResult(
          ok: false, status: 'error', uuid: uuid,
          error: _err(data) ?? 'Cancel failed (${res.status})',
        );
      }
      final inner = data['data'] as Map<String, dynamic>? ?? {};
      // LHDN echoes the new status ("Cancelled"); treat any ok response as done.
      return MyInvoisResult(
        ok: true, status: (inner['status'] ?? 'Cancelled').toString(), uuid: uuid);
    } catch (e) {
      return MyInvoisResult(ok: false, status: 'error', uuid: uuid, error: e.toString());
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
