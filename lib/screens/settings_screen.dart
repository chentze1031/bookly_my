import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../screens/auth_screen.dart';
import 'ai_screen.dart';
import 'bank_import_screen.dart';
import 'company_info_screen.dart';
import 'sst_report_screen.dart';
import 'sub_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sub = context.watch<SubState>();
    final t   = L10n(app.settings.lang);
    final s   = app.settings;
    final uid = app.currentUid; // null = guest

    void upd(AppSettings ns) => app.updateSettings(ns);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
      children: [

        // ── Offline banner ──────────────────────────────────────────────
        if (!app.isOnline)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              border: Border.all(color: const Color(0xFFFFE083)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Text('📶', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Offline Mode',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  if (app.pendingOps > 0)
                    Text('${app.pendingOps} change(s) pending sync',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF856404))),
                ],
              )),
              if (app.pendingOps > 0)
                TextButton(
                  onPressed: app.onReconnect,
                  child: const Text('Sync now',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),

        // ── Account block ────────────────────────────────────────────────
        SectionCard(
          title: '👤 Account',
          child: uid != null
            ? _LoggedInTile(app: app, t: t)
            : _GuestTile(app: app, t: t),
        ),

        // ── Subscription block ──────────────────────────────────────────
        if (sub.isPro)
          _ProBlock(sub: sub, t: t)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GestureDetector(
              onTap: () => showSubSheet(context),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  const Text('✦', style: TextStyle(fontSize: 28, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.proTitle,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                      const Text('Remove all ads · Support development',
                        style: TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                    ],
                  )),
                  const Text('→', style: TextStyle(color: Colors.white, fontSize: 18)),
                ]),
              ),
            ),
          ),

        // ── Company Info ────────────────────────────────────────────────
        SectionCard(
          title: '🏢 ${t.coName}',
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: s.logoBase64 != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(s.logoBase64!.split(',').last),
                    width: 40, height: 40, fit: BoxFit.cover,
                    errorBuilder: (_,__,___) =>
                        const Text('🏢', style: TextStyle(fontSize: 28)),
                  ),
                )
              : const Text('🏢', style: TextStyle(fontSize: 28)),
            title: Text(
              s.companyName.isNotEmpty ? s.companyName
                : (t.isZh ? '未设置' : 'Not set'),
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color: s.companyName.isNotEmpty ? kText : kMuted),
            ),
            subtitle: Text(
              s.coPhone.isNotEmpty ? s.coPhone
                : (t.isZh ? '点击编辑公司资料' : 'Tap to edit company info'),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CompanyInfoScreen())),
          ),
        ),

        // ── SST-02 Report ────────────────────────────────────────────────
        SectionCard(
          title: '🧾 ${t.isZh ? "SST-02 申报摘要" : "SST-02 Tax Summary"}',
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const Text('📊', style: TextStyle(fontSize: 28)),
            title: Text(
              t.isZh ? 'SST-02 双月申报摘要' : 'Bi-Monthly SST-02 Summary',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText),
            ),
            subtitle: Text(
              t.isZh ? '按税率汇总应税销售额与 SST' : 'Taxable sales & SST grouped by rate',
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SstReportScreen())),
          ),
        ),

        // ── Language ────────────────────────────────────────────────────
        SectionCard(
          title: '🌐 ${t.lang}',
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              for (final lng in [('en','EN'), ('zh','中文')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => upd(s.copyWith(lang: lng.$1)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: s.lang == lng.$1 ? kDark : kBg,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: kBorder),
                      ),
                      child: Text(lng.$2, style: TextStyle(
                        color: s.lang == lng.$1 ? Colors.white : kMuted,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
            ]),
          ),
        ),

        // ── FX Rates ────────────────────────────────────────────────────
        SectionCard(
          title: '💱 ${t.fxLive}',
          child: Column(children: [
            _FxStatusBar(app: app),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 6, runSpacing: 6,
                children: defaultRates.keys.where((c) => c != 'MYR').map((code) =>
                  Container(
                    width: 130,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: kBg, border: Border.all(color: kBorder),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(children: [
                      Text('${currencyFlags[code] ?? ''} ',
                          style: const TextStyle(fontSize: 13)),
                      Text(code, style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700, color: kMuted)),
                      const SizedBox(width: 4),
                      Expanded(child: Text(
                        (app.fxRates[code] ?? 0).toStringAsFixed(4),
                        style: const TextStyle(
                            fontSize: 11, color: kText, fontFamily: 'monospace'),
                      )),
                    ]),
                  ),
                ).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: OutlinedButton.icon(
                onPressed: app.resetFxRates,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(t.fxReset),
              ),
            ),
          ]),
        ),

        // ── Tools & AI ──────────────────────────────────────────────────
        SectionCard(
          title: '🛠️  Tools',
          child: Column(children: [
            ListTile(
              leading: const Text('✨', style: TextStyle(fontSize: 22)),
              title: const Text('AI Assistant',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Auto-categorise & cash flow forecast',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiScreen())),
            ),
            const Divider(height: 1, color: kBorder, indent: 16),
            ListTile(
              leading: const Text('🏦', style: TextStyle(fontSize: 22)),
              title: const Text('Bank Statement Import',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Import PDF bank statement via AI',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankImportScreen())),
            ),
          ]),
        ),

        // ── Version ─────────────────────────────────────────────────────
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text('Bookly MY',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
            Text('v1.0 · Malaysia Edition · Flutter',
                style: TextStyle(fontSize: 11, color: kMuted)),
          ]),
        ),
      ],
    );
  }

}

// ── Logged-in account tile ────────────────────────────────────────────────────
class _LoggedInTile extends StatelessWidget {
  final AppState app;
  final L10n t;
  const _LoggedInTile({required this.app, required this.t});

  @override
  Widget build(BuildContext context) {
    final user  = app.currentUser;
    final email = user?.email ?? '';
    final name  = user?.userMetadata?['full_name'] ?? email;
    final avatar = user?.userMetadata?['avatar_url'];

    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: avatar != null
          ? ClipOval(child: Image.network(avatar, width: 42, height: 42, fit: BoxFit.cover,
              errorBuilder: (_,__,___) => const CircleAvatar(child: Icon(Icons.person))))
          : const CircleAvatar(backgroundColor: kBorder, child: Icon(Icons.person, color: kMuted)),
        title: Text(name.toString(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(email,
          style: const TextStyle(fontSize: 12, color: kMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: kGreenBg, border: Border.all(color: kGreenBd),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text('●  Synced',
            style: TextStyle(fontSize: 11, color: kGreen, fontWeight: FontWeight.w700)),
        ),
      ),
      const Divider(height: 1, color: kBorder, indent: 16),
      // Sign out button
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: const Icon(Icons.logout, color: kRed, size: 20),
        title: Text(t.isZh ? '登出' : 'Sign Out',
          style: const TextStyle(color: kRed, fontWeight: FontWeight.w600, fontSize: 14)),
        onTap: () => _confirmSignOut(context),
      ),
    ]);
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final sub = context.read<SubState>();
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t.isZh ? '确认登出？' : 'Sign Out?'),
        content: Text(t.isZh
          ? '登出后本地数据将被清除。\n云端数据仍然保留。'
          : 'Local data will be cleared after signing out.\nYour cloud data remains safe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(t.isZh ? '取消' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(t.isZh ? '登出' : 'Sign Out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try { await sub.forgetUser(); } catch (_) {}
      bool pushed = true;
      try { pushed = await app.signOut(); } catch (_) { pushed = false; }
      // FIX(数据丢失): 若云端推送失败，本地数据已保留，提示用户。
      if (!pushed && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.isZh
            ? '⚠️ 数据未能上传到云端，已保留在本机。请联网后重新登录同步。'
            : 'Data could not be synced to cloud; kept on this device. Re-login when online to sync.'),
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }
}

// ── Guest account tile ────────────────────────────────────────────────────────
class _GuestTile extends StatelessWidget {
  final AppState app;
  final L10n t;
  const _GuestTile({required this.app, required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: const CircleAvatar(
          backgroundColor: kBorder,
          child: Icon(Icons.person_outline, color: kMuted)),
        title: Text(t.isZh ? '访客模式' : 'Guest Mode',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(t.isZh ? '数据仅保存在本设备' : 'Data saved on this device only',
          style: const TextStyle(fontSize: 12, color: kMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            border: Border.all(color: const Color(0xFFFFE083)),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text('⚠ Local only',
            style: TextStyle(fontSize: 11, color: Color(0xFF856404), fontWeight: FontWeight.w700)),
        ),
      ),
      const Divider(height: 1, color: kBorder, indent: 16),
      // Sign in button
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            label: Text(t.isZh ? '登录并同步数据' : 'Sign in & Sync Data',
              style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => _signInAndMigrate(context),
          ),
        ),
      ),
    ]);
  }

  Future<void> _signInAndMigrate(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(t.isZh ? '登录 Google？' : 'Sign in with Google?'),
        content: Text(t.isZh
          ? '登录后，您的本地数据将自动上传到云端，可在多设备使用。'
          : 'Your local data will be uploaded to the cloud so you can access it on any device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(t.isZh ? '取消' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(t.isZh ? '继续' : 'Continue'),
          ),
        ],
      ),
    );
    if (ok == true) guestMode.value = false;
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────
class _ProBlock extends StatelessWidget {
  final SubState sub;
  final L10n t;
  const _ProBlock({required this.sub, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('✦', style: TextStyle(fontSize: 24, color: Colors.white)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.proTitle, style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(t.monthly, style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
        ]),
        const Spacer(),
        const ProBadge(),
      ]),
      if (sub.proExpires != null) ...[
        const SizedBox(height: 8),
        Text('${t.isZh ? '到期时间' : 'Expires'}: ${sub.proExpires}',
            style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
      ],
      const SizedBox(height: 10),
      Text(t.manageSub, style: const TextStyle(
          color: Color(0x80FFFFFF), fontSize: 12, decoration: TextDecoration.underline)),
    ]),
  );
}

class _FxStatusBar extends StatelessWidget {
  final AppState app;
  const _FxStatusBar({required this.app});

  @override
  Widget build(BuildContext context) {
    final ok  = app.fxStatus == FxStatus.ok;
    final err = app.fxStatus == FxStatus.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? kGreenBg : err ? kRedBg : kBg,
        border: Border.all(color: ok ? kGreenBd : err ? kRedBd : kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            app.fxStatus == FxStatus.loading ? '⏳ Fetching…'
              : ok ? '✓ Live rates' : '⚠ Offline',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: ok ? kGreen : err ? kRed : kMuted)),
          if (app.fxUpdatedAt != null)
            Text('Updated: ${app.fxUpdatedAt}',
                style: const TextStyle(fontSize: 10, color: kMuted)),
        ])),
        ElevatedButton(
          onPressed: app.fxStatus == FxStatus.loading ? null : app.fetchFxRates,
          style: ElevatedButton.styleFrom(
            backgroundColor: kDark, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('↺', style: TextStyle(fontSize: 14)),
        ),
      ]),
    );
  }
}
