import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── Install-referrer attribution (Google Play) ─────────────────────────────
  // A shared link of the form
  //   https://play.google.com/store/apps/details?id=com.bookly.my&referrer=ref%3DCODE
  // lets Google Play hand the `ref=CODE` string to the app on first launch, so
  // a friend who installs via the link is auto-credited — no manual code entry.
  // Only works for Play-installed builds; sideloaded APKs fall back to manual.
  static const _kPendingCode     = 'referral_pending_code';
  static const _kReferrerChecked = 'referral_referrer_checked';

  /// Read the Play install referrer ONCE and cache any embedded `ref=CODE`.
  /// Safe to call every launch — no-ops after the first read and on non-Play
  /// installs. Call early in main() (fire-and-forget).
  static Future<void> captureInstallReferrer() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kReferrerChecked) == true) return;
    try {
      final details = await PlayInstallReferrer.installReferrer;
      final code = _extractCode(details.installReferrer);
      if (code != null && code.isNotEmpty) {
        await prefs.setString(_kPendingCode, code);
      }
    } catch (_) {
      // iOS / no Play Services / sideloaded — nothing to capture.
    }
    await prefs.setBool(_kReferrerChecked, true);
  }

  static String? _extractCode(String? referrer) {
    if (referrer == null || referrer.isEmpty) return null;
    for (final part in referrer.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      if (part.substring(0, i) == 'ref') {
        return Uri.decodeComponent(part.substring(i + 1)).trim().toUpperCase();
      }
    }
    return null;
  }

  /// If a code was captured from the install referrer, submit it once the user
  /// is signed in (and not already referred), then clear it. Kept only on a
  /// transient network error so it retries next launch. Call after login.
  static Future<void> applyPendingReferral() async {
    if (_sb.auth.currentUser == null) return;
    await captureInstallReferrer(); // ensure the referrer was read at least once
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kPendingCode);
    if (code == null || code.isEmpty) return;
    final result = await submitCode(code);
    if (result != 'error') {
      await prefs.remove(_kPendingCode); // ok / already_linked / self_referral / invalid
    }
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
