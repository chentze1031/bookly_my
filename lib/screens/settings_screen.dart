import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../state/accounting_state.dart';
import '../services/inventory_service.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../screens/auth_screen.dart';
import 'company_info_screen.dart';
import 'sst_report_screen.dart';
import 'sub_screen.dart';
import 'recurring_screen.dart';

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
              color: kGoldBg,
              border: Border.all(color: kGoldBd),
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
                      style: TextStyle(fontSize: 11, color: kGold)),
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

        // ── Company ledgers (Phase 4 #24, Pro) ───────────────────────────
        _CompanyBlock(app: app, t: t, isPro: sub.isPro),

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
                : (tr(t.lang, 'Not set', '未设置', 'Tidak ditetapkan')),
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color: s.companyName.isNotEmpty ? kText : kMuted),
            ),
            subtitle: Text(
              s.coPhone.isNotEmpty ? s.coPhone
                : (tr(t.lang, 'Tap to edit company info', '点击编辑公司资料', 'Ketik untuk sunting maklumat syarikat')),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CompanyInfoScreen())),
          ),
        ),

        // ── SST-02 Report ────────────────────────────────────────────────
        SectionCard(
          title: '🧾 ${tr(t.lang, "SST-02 Tax Summary", "SST-02 申报摘要", "Ringkasan Cukai SST-02")}',
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const Text('📊', style: TextStyle(fontSize: 28)),
            title: Text(
              tr(t.lang, 'Bi-Monthly SST-02 Summary', 'SST-02 双月申报摘要', 'Ringkasan SST-02 Dwi-Bulan'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText),
            ),
            subtitle: Text(
              tr(t.lang, 'Taxable sales & SST grouped by rate', '按税率汇总应税销售额与 SST', 'Jualan bercukai & SST mengikut kadar'),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SstReportScreen())),
          ),
        ),

        // ── Recurring transactions (Phase 4 #21, Pro) ────────────────────
        SectionCard(
          title: '🔁 ${tr(t.lang, "Recurring", "定期记账", "Berulang")}',
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: const Text('🔁', style: TextStyle(fontSize: 28)),
            title: Text(
              tr(t.lang, 'Recurring Transactions', '定期自动记账', 'Transaksi Berulang'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText),
            ),
            subtitle: Text(
              tr(t.lang, 'Auto-create rent, subscriptions monthly/weekly', '租金、订阅等按月/周自动生成', 'Auto-jana sewa, langganan bulanan/mingguan'),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: sub.isPro
              ? const Icon(Icons.chevron_right, color: kMuted)
              : Icon(Icons.lock_outline, size: 18, color: kPro),
            onTap: () => sub.isPro
              ? Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen()))
              : showSubSheet(context),
          ),
        ),

        // ── Language ────────────────────────────────────────────────────
        SectionCard(
          title: '🌐 ${t.langLabel}',
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              for (final lng in [('en','EN'), ('zh','中文'), ('ms','BM')])
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

        // ── Theme (Phase 4 #23) ──────────────────────────────────────────
        SectionCard(
          title: '🌗 ${tr(t.lang, 'Theme', '主题', 'Tema')}',
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            value: s.dark,
            activeColor: kDark,
            title: Text(tr(t.lang, 'Dark mode', '深色模式', 'Mod Gelap'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
            subtitle: Text(tr(t.lang, 'Easier on the eyes at night', '夜间护眼', 'Lebih selesa pada waktu malam'),
              style: const TextStyle(fontSize: 12, color: kMuted)),
            onChanged: (v) => upd(s.copyWith(dark: v)),
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
                        style: TextStyle(
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

        // ── Version ─────────────────────────────────────────────────────
        Padding(
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

// ── Company ledgers block (Phase 4 #24) ──────────────────────────────────────
class _CompanyBlock extends StatelessWidget {
  final AppState app;
  final L10n t;
  final bool isPro;
  const _CompanyBlock({required this.app, required this.t, required this.isPro});

  // After switching, reload the other per-company stores too.
  Future<void> _reloadOthers(BuildContext ctx) async {
    await ctx.read<AccountingState>().init();
    await ctx.read<InventoryState>().load();
  }

  Future<void> _switch(BuildContext ctx, String id) async {
    if (id == app.activeCompany) return;
    await app.switchCompany(id);
    if (!ctx.mounted) return;
    await _reloadOthers(ctx);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(tr(t.lang, 'Switched to ${app.activeCompanyObj.name}',
          '已切换到 ${app.activeCompanyObj.name}', 'Bertukar ke ${app.activeCompanyObj.name}')),
      behavior: SnackBarBehavior.floating, backgroundColor: kDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<String?> _nameDialog(BuildContext ctx,
      {String initial = '', required String title}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(title, style: TextStyle(color: kText, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: kText),
          decoration: InputDecoration(
            hintText: tr(t.lang, 'Company name', '公司名称', 'Nama syarikat')),
          onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx),
            child: Text(tr(t.lang, 'Cancel', '取消', 'Batal'))),
          TextButton(onPressed: () => Navigator.pop(dctx, ctrl.text.trim()),
            child: Text(tr(t.lang, 'Save', '保存', 'Simpan'))),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext ctx) async {
    final name = await _nameDialog(ctx,
        title: tr(t.lang, 'New Company', '新建公司', 'Syarikat Baru'));
    if (name == null || name.isEmpty || !ctx.mounted) return;
    final id = await app.createCompany(name);
    if (ctx.mounted) await _switch(ctx, id); // jump into the new ledger
  }

  Future<void> _rename(BuildContext ctx, Company c) async {
    final name = await _nameDialog(ctx, initial: c.name,
        title: tr(t.lang, 'Rename Company', '重命名公司', 'Namakan Semula'));
    if (name == null || name.isEmpty) return;
    await app.renameCompany(c.id, name);
  }

  Future<void> _delete(BuildContext ctx, Company c) async {
    final ok = await showConfirmDialog(
      context: ctx,
      title: tr(t.lang, 'Delete company?', '删除公司？', 'Padam syarikat?'),
      message: tr(t.lang,
        'All data for "${c.name}" on this device will be permanently deleted.',
        '本设备上「${c.name}」的所有数据将被永久删除。',
        'Semua data "${c.name}" pada peranti ini akan dipadam kekal.'),
      confirmLabel: tr(t.lang, 'Delete', '删除', 'Padam'),
      cancelLabel: tr(t.lang, 'Cancel', '取消', 'Batal'),
    );
    if (ok != true) return;
    await app.deleteCompany(c.id);
    if (ctx.mounted) await _reloadOthers(ctx);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '🏢 ${tr(t.lang, 'Company Ledgers', '公司账本', 'Lejar Syarikat')}',
      child: Column(children: [
        ...app.companies.map((c) {
          final active = c.id == app.activeCompany;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Icon(active ? Icons.check_circle : Icons.business_outlined,
                color: active ? kGreen : kMuted),
            title: Text(c.name,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText)),
            subtitle: active
                ? Text(tr(t.lang, 'Active', '使用中', 'Aktif'),
                    style: TextStyle(fontSize: 11, color: kGreen, fontWeight: FontWeight.w600))
                : null,
            onTap: () => _switch(context, c.id),
            trailing: c.isDefault
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 18, color: kMuted),
                      onPressed: () => _rename(context, c)),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: kRed),
                      onPressed: () => _delete(context, c)),
                  ]),
          );
        }),
        Divider(height: 1, color: kBorder),
        InkWell(
          onTap: () => isPro ? _add(context) : showSubSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Icon(Icons.add, color: kBlue, size: 20),
              const SizedBox(width: 8),
              Text(tr(t.lang, 'Add company', '添加公司', 'Tambah syarikat'),
                  style: TextStyle(color: kBlue, fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              if (!isPro)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: kPro, borderRadius: BorderRadius.circular(99)),
                  child: const Text('PRO',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
        ),
      ]),
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
          : CircleAvatar(backgroundColor: kBorder, child: Icon(Icons.person, color: kMuted)),
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
          child: Text('●  Synced',
            style: TextStyle(fontSize: 11, color: kGreen, fontWeight: FontWeight.w700)),
        ),
      ),
      Divider(height: 1, color: kBorder, indent: 16),
      // Sign out button
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: Icon(Icons.logout, color: kRed, size: 20),
        title: Text(tr(t.lang, 'Sign Out', '登出', 'Log Keluar'),
          style: TextStyle(color: kRed, fontWeight: FontWeight.w600, fontSize: 14)),
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
        title: Text(tr(t.lang, 'Sign Out?', '确认登出？', 'Log Keluar?')),
        content: Text(tr(t.lang,
          'Local data will be cleared after signing out.\nYour cloud data remains safe.',
          '登出后本地数据将被清除。\n云端数据仍然保留。',
          'Data tempatan akan dipadam selepas log keluar.\nData awan anda kekal selamat.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(tr(t.lang, 'Cancel', '取消', 'Batal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(tr(t.lang, 'Sign Out', '登出', 'Log Keluar')),
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
          content: Text(tr(t.lang,
            'Data could not be synced to cloud; kept on this device. Re-login when online to sync.',
            '⚠️ 数据未能上传到云端，已保留在本机。请联网后重新登录同步。',
            'Data tidak dapat disegerakkan ke awan; disimpan pada peranti ini. Log masuk semula bila dalam talian.')),
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
        leading: CircleAvatar(
          backgroundColor: kBorder,
          child: Icon(Icons.person_outline, color: kMuted)),
        title: Text(tr(t.lang, 'Guest Mode', '访客模式', 'Mod Tetamu'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(tr(t.lang, 'Data saved on this device only', '数据仅保存在本设备', 'Data disimpan pada peranti ini sahaja'),
          style: const TextStyle(fontSize: 12, color: kMuted)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: kGoldBg,
            border: Border.all(color: kGoldBd),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text('⚠ Local only',
            style: TextStyle(fontSize: 11, color: kGold, fontWeight: FontWeight.w700)),
        ),
      ),
      Divider(height: 1, color: kBorder, indent: 16),
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
            label: Text(tr(t.lang, 'Sign in & Sync Data', '登录并同步数据', 'Log masuk & Segerak Data'),
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
        title: Text(tr(t.lang, 'Sign in with Google?', '登录 Google？', 'Log masuk dengan Google?')),
        content: Text(tr(t.lang,
          'Your local data will be uploaded to the cloud so you can access it on any device.',
          '登录后，您的本地数据将自动上传到云端，可在多设备使用。',
          'Data tempatan anda akan dimuat naik ke awan supaya boleh diakses pada mana-mana peranti.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(tr(t.lang, 'Cancel', '取消', 'Batal')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(tr(t.lang, 'Continue', '继续', 'Teruskan')),
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
        Text('${tr(t.lang, 'Expires', '到期时间', 'Tamat Tempoh')}: ${sub.proExpires}',
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
