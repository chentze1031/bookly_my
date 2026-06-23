import 'package:supabase_flutter/supabase_flutter.dart';

// ════════════════════════════════════════════════════════════════════════════
// REFERRAL SERVICE — talks to the `referral` Supabase Edge Function.
//
// Every signed-in user has a 6-char invite code. A referee links to a referrer
// by code; once the referee becomes ACTIVE (≥3 transactions), the referrer's
// reward tier is re-evaluated and granted as a RevenueCat promotional `pro`
// entitlement. Reward = HIGHEST tier reached (not additive):
//   1 active referral → 7 days · 5 → 2 months · 10 → 6 months · 20 → 1 year
//
// All writes go through the Edge Function (service role); the client only
// carries the user's JWT (functions.invoke attaches it automatically).
// Backend: supabase/functions/referral + supabase/referral_setup.sql.
// ════════════════════════════════════════════════════════════════════════════
class ReferralService {
  static final _sb = Supabase.instance.client;

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final res = await _sb.functions.invoke('referral', body: body);
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Current user's invite code + referral progress.
  /// Returns null when not logged in or on any error.
  static Future<ReferralInfo?> me() async {
    if (_sb.auth.currentUser == null) return null;
    try {
      final d = await _call({'action': 'me'});
      if (d['code'] == null) return null;
      return ReferralInfo(
        code:           d['code'] as String,
        referredBy:     d['referredBy'] as String?,
        grantedTier:    (d['grantedTier'] as num?)?.toInt() ?? 0,
        validReferrals: (d['validReferrals'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Link the signed-in user to a referrer by their invite code.
  /// Returns 'ok' on success, otherwise an error key:
  /// no_code | invalid_code | self_referral | already_linked | error.
  static Future<String> submitCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return 'no_code';
    try {
      final d = await _call({'action': 'link', 'code': trimmed});
      if (d['ok'] == true) return 'ok';
      return (d['error'] as String?) ?? 'error';
    } on FunctionException catch (e) {
      final det = e.details;
      if (det is Map && det['error'] != null) return det['error'].toString();
      return 'error';
    } catch (_) {
      return 'error';
    }
  }

  /// Mark this user active (once ≥3 tx) so their referrer can be rewarded.
  /// Best-effort, fire-and-forget; call once on app launch after login.
  static Future<void> sync() async {
    if (_sb.auth.currentUser == null) return;
    try {
      await _call({'action': 'sync'});
    } catch (_) {}
  }
}

class ReferralInfo {
  final String code;
  final String? referredBy;
  final int grantedTier;     // highest tier already rewarded (0/1/5/10/20)
  final int validReferrals;  // active referees counted toward your reward

  const ReferralInfo({
    required this.code,
    this.referredBy,
    required this.grantedTier,
    required this.validReferrals,
  });

  bool get isReferred => referredBy != null;
}
