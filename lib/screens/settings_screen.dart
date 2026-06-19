import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../state/accounting_state.dart';
import '../services/inventory_service.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../screens/auth_screen.dart';
import '../services/myinvois_service.dart';
import '../services/cert_service.dart';
import 'consolidated_einvoice_screen.dart';
import 'self_billed_einvoice_screen.dart';
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

        // ── Bookly PRO (moved to top — user request) ─────────────────────
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

        // ── Account block ────────────────────────────────────────────────
        SectionCard(
          title: '👤 Account',
          child: uid != null
            ? _LoggedInTile(app: app, t: t)
            : _GuestTile(app: app, t: t),
        ),

        // ── Company: ledgers + active-company profile merged (Phase 4 #24)
        // 当前公司显示业务名/logo/电话+使用中，点击 → 编辑公司资料；
        // 其他公司点击切换；底部 + 添加公司。
        _CompanyBlock(app: app, t: t, isPro: sub.isPro),

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

        // ── MyInvois e-Invoice (Phase 4 #28, Pro) ────────────────────────
        SectionCard(
          title: '🧾 ${tr(t.lang, "MyInvois e-Invoice", "MyInvois 电子发票", "e-Invois MyInvois")}',
          child: _MyInvoisCard(lang: t.lang, isPro: sub.isPro, loggedIn: uid != null),
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
    final s = app.settings;
    return SectionCard(
      title: '🏢 ${tr(t.lang, 'Company', '公司', 'Syarikat')}',
      child: Column(children: [
        ...app.companies.map((c) {
          final active = c.id == app.activeCompany;
          if (active) {
            // 当前公司 = 业务资料卡：logo + 业务名 + 电话 + 使用中，点击进编辑。
            final hasName = s.companyName.isNotEmpty;
            return ListTile(
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
                hasName ? s.companyName : c.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14,
                  color: hasName ? kText : kMuted)),
              subtitle: Text(
                s.coPhone.isNotEmpty ? s.coPhone
                  : tr(t.lang, 'Tap to edit company info', '点击编辑公司资料', 'Ketik untuk sunting maklumat'),
                style: const TextStyle(fontSize: 12, color: kMuted)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kGreenBg, borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: kGreenBd)),
                  child: Text('●  ${tr(t.lang, 'Active', '使用中', 'Aktif')}',
                    style: TextStyle(fontSize: 10, color: kGreen, fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_right, color: kMuted),
              ]),
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CompanyInfoScreen())),
            );
          }
          // 其他公司：点击切换；非默认账本可重命名/删除。
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Icon(Icons.business_outlined, color: kMuted),
            title: Text(c.name,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText)),
            subtitle: Text(tr(t.lang, 'Tap to switch', '点击切换', 'Ketik untuk tukar'),
                style: const TextStyle(fontSize: 11, color: kMuted)),
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

// ─── MyInvois e-Invoice config (Phase 4 #28) ─────────────────────────────────
class _MyInvoisCard extends StatefulWidget {
  final String lang;
  final bool isPro, loggedIn;
  const _MyInvoisCard({required this.lang, required this.isPro, required this.loggedIn});
  @override State<_MyInvoisCard> createState() => _MyInvoisCardState();
}

class _MyInvoisCardState extends State<_MyInvoisCard> {
  final _clientId = TextEditingController();
  final _secret   = TextEditingController();
  final _msic     = TextEditingController();
  final _msicDesc = TextEditingController();
  final _class    = TextEditingController();
  String _env = 'sandbox';
  bool _secretSet = false;
  bool _saving = false;
  bool _loaded = false;
  CertInfo? _cert;
  bool _certBusy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _msic.text = s.msicCode;
    _msicDesc.text = s.msicDesc;
    _class.text = s.classCode;
    _load();
  }

  Future<void> _load() async {
    if (!widget.loggedIn) { setState(() => _loaded = true); return; }
    try {
      final creds = await MyInvoisService.loadCredentials();
      if (creds != null && mounted) {
        _clientId.text = (creds['client_id'] ?? '') as String;
        _env = (creds['env'] ?? 'sandbox') as String;
        _secretSet = (creds['client_id'] ?? '').toString().isNotEmpty;
      }
    } catch (_) {}
    await _loadCert();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _loadCert() async {
    try {
      _cert = await CertService.info();
    } catch (_) {
      _cert = null;
    }
  }

  Future<void> _importCert() async {
    final lang = widget.lang;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['p12', 'pfx', 'pem'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;

    String? password;
    final name = f.name.toLowerCase();
    if (name.endsWith('.p12') || name.endsWith('.pfx')) {
      password = await _askPassword();
      if (password == null) return; // cancelled
    }

    setState(() => _certBusy = true);
    final err = await CertService.importBytes(bytes, password: password, filename: f.name);
    await _loadCert();
    if (mounted) {
      setState(() => _certBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ??
            tr(lang, 'Certificate imported', '证书已导入', 'Sijil diimport')),
        backgroundColor: err == null ? kDark : kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<String?> _askPassword() async {
    final lang = widget.lang;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(lang, 'Certificate password', '证书密码', 'Kata laluan sijil'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, obscureText: true, autofocus: true,
          decoration: _dec(tr(lang, '.p12 / .pfx password', '.p12 / .pfx 密码', 'kata laluan .p12 / .pfx')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(lang, 'Cancel', '取消', 'Batal'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr(lang, 'OK', '确定', 'OK'))),
        ],
      ),
    );
  }

  Future<void> _removeCert() async {
    final lang = widget.lang;
    final ok = await showConfirmDialog(
      context: context,
      title: tr(lang, 'Remove certificate?', '移除证书？', 'Buang sijil?'),
      message: tr(lang,
          'Invoices will be submitted unsigned (sandbox only) until you import a certificate again.',
          '在重新导入证书前，发票将以未签名方式提交（仅限沙盒）。',
          'Invois akan dihantar tanpa tandatangan (sandbox sahaja) sehingga sijil diimport semula.'),
      confirmLabel: tr(lang, 'Remove', '移除', 'Buang'),
    );
    if (ok != true) return;
    await CertService.clear();
    await _loadCert();
    if (mounted) setState(() {});
  }

  Widget _buildCertBox(String lang) {
    if (_certBusy) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    final c = _cert;
    if (c == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(lang,
          'No certificate. Invoices submit unsigned (sandbox only). Import your LHDN-CA certificate (.p12/.pfx or .pem) to sign for production. The private key stays on this device.',
          '未导入证书。发票将以未签名提交（仅限沙盒）。导入你的 LHDN 认可 CA 证书（.p12/.pfx 或 .pem）以便正式环境签名。私钥只保存在本机。',
          'Tiada sijil. Invois dihantar tanpa tandatangan (sandbox sahaja). Import sijil CA LHDN anda (.p12/.pfx atau .pem) untuk tandatangan produksi. Kunci peribadi kekal di peranti ini.'),
          style: const TextStyle(fontSize: 12, color: kMuted)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _importCert,
          icon: const Icon(Icons.upload_file, size: 18),
          style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: BorderSide(color: kBlueBd)),
          label: Text(tr(lang, 'Import certificate', '导入证书', 'Import sijil')),
        ),
      ]);
    }
    final bad = c.expired || c.notYetValid;
    final soon = !bad && c.daysLeft <= 30;
    final tone = bad ? kRed : (soon ? kGold : kGreen);
    final toneBg = bad ? kRedBg : (soon ? kGoldBg : kGreenBg);
    final until = '${c.notAfter.year}-${c.notAfter.month.toString().padLeft(2, '0')}-${c.notAfter.day.toString().padLeft(2, '0')}';
    String statusTxt;
    if (c.expired) {
      statusTxt = tr(lang, 'EXPIRED', '已过期', 'TAMAT TEMPOH');
    } else if (c.notYetValid) {
      statusTxt = tr(lang, 'NOT YET VALID', '尚未生效', 'BELUM SAH');
    } else if (soon) {
      statusTxt = tr(lang, 'Expires in ${c.daysLeft} days', '${c.daysLeft} 天后过期', 'Tamat dalam ${c.daysLeft} hari');
    } else {
      statusTxt = tr(lang, 'Valid until $until', '有效至 $until', 'Sah hingga $until');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: toneBg, border: Border.all(color: tone.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(bad ? Icons.error_outline : Icons.verified_user, size: 18, color: tone),
          const SizedBox(width: 6),
          Expanded(child: Text(statusTxt, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tone))),
        ]),
        const SizedBox(height: 6),
        Text(c.subject, style: const TextStyle(fontSize: 11, color: kMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: _importCert, child: Text(tr(lang, 'Replace', '替换', 'Ganti'))),
          const SizedBox(width: 4),
          TextButton(onPressed: _removeCert,
            child: Text(tr(lang, 'Remove', '移除', 'Buang'), style: TextStyle(color: kRed))),
        ]),
      ]),
    );
  }

  @override
  void dispose() {
    _clientId.dispose(); _secret.dispose(); _msic.dispose(); _msicDesc.dispose();
    _class.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final app = context.read<AppState>();
    try {
      await MyInvoisService.saveCredentials(
        clientId: _clientId.text, clientSecret: _secret.text, env: _env);
      await app.updateSettings(app.settings.copyWith(
        msicCode: _msic.text.trim(), msicDesc: _msicDesc.text.trim(),
        classCode: _class.text.trim().isEmpty ? '022' : _class.text.trim()));
      if (mounted) {
        _secret.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr(widget.lang, 'MyInvois settings saved', 'MyInvois 设置已保存', 'Tetapan MyInvois disimpan')),
          backgroundColor: kDark, behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(widget.lang, 'Save failed', '保存失败', 'Gagal simpan')}: $e'), backgroundColor: kRed));
    }
    if (mounted) setState(() => _saving = false);
  }

  InputDecoration _dec(String hint) => InputDecoration(
    isDense: true, hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: kMuted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kBorder)),
  );

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    if (!widget.loggedIn) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          tr(lang, 'Sign in to configure MyInvois e-Invoice.', '登录后才能配置 MyInvois 电子发票。', 'Log masuk untuk konfigurasi e-Invois MyInvois.'),
          style: const TextStyle(fontSize: 13, color: kMuted)),
      );
    }
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.all(20),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    Widget label(String txt) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 5),
      child: Text(txt, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: .3)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(lang,
          'Submit invoices to LHDN MyInvois. Get your API client ID/secret from the MyInvois portal.',
          '将发票提交到 LHDN MyInvois。在 MyInvois 门户获取 API client ID/secret。',
          'Hantar invois ke LHDN MyInvois. Dapatkan client ID/secret API dari portal MyInvois.'),
          style: const TextStyle(fontSize: 12, color: kMuted)),

        // Environment toggle
        label(tr(lang, 'ENVIRONMENT', '环境', 'PERSEKITARAN')),
        Row(children: [
          for (final e in [('sandbox', tr(lang, 'Test Mode', '测试模式', 'Mod Ujian')), ('prod', tr(lang, 'Live Mode', '正式模式', 'Mod Sebenar'))])
            Padding(padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _env = e.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: _env == e.$1 ? kDark : kBg,
                    borderRadius: BorderRadius.circular(99), border: Border.all(color: kBorder)),
                  child: Text(e.$2, style: TextStyle(
                    color: _env == e.$1 ? Colors.white : kMuted, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              )),
        ]),
        // Mode hint — switches with the selected environment.
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _env == 'prod'
              ? tr(lang,
                  'Live mode — this runs your real business. All data is genuinely submitted to LHDN (the tax authority).',
                  '此模式为实际业务运行，所有数据将真实提交给税局。',
                  'Mod sebenar — operasi perniagaan sebenar. Semua data dihantar betul-betul kepada LHDN (pihak cukai).')
              : tr(lang,
                  'For functional testing only. Data has no legal effect and is not submitted to LHDN.',
                  '此模式仅供功能测试，数据不具有法律效力，不会提交给税局。',
                  'Untuk ujian fungsi sahaja. Data tiada kesan undang-undang dan tidak dihantar kepada LHDN.'),
            style: TextStyle(fontSize: 11, color: _env == 'prod' ? kRed : kMuted, height: 1.4),
          ),
        ),

        label('CLIENT ID'),
        TextField(controller: _clientId, style: TextStyle(fontSize: 13, color: kText), decoration: _dec('xxxxxxxx-xxxx-...')),
        label('CLIENT SECRET'),
        TextField(controller: _secret, obscureText: true, style: TextStyle(fontSize: 13, color: kText),
          decoration: _dec(_secretSet
            ? tr(lang, '•••• (leave blank to keep)', '•••• (留空则不变)', '•••• (kosong = kekal)')
            : tr(lang, 'Enter client secret', '输入 client secret', 'Masukkan client secret'))),
        label(tr(lang, 'MSIC CODE', 'MSIC 行业码', 'KOD MSIC')),
        TextField(controller: _msic, keyboardType: TextInputType.number, style: TextStyle(fontSize: 13, color: kText), decoration: _dec('e.g. 46900')),
        label(tr(lang, 'BUSINESS ACTIVITY', '业务活动描述', 'AKTIVITI PERNIAGAAN')),
        TextField(controller: _msicDesc, style: TextStyle(fontSize: 13, color: kText), decoration: _dec(tr(lang, 'e.g. Wholesale trade', '例如：批发贸易', 'cth. Perdagangan borong'))),
        label(tr(lang, 'DEFAULT CLASSIFICATION CODE', '默认商品分类码', 'KOD KLASIFIKASI LALAI')),
        TextField(controller: _class, keyboardType: TextInputType.number, style: TextStyle(fontSize: 13, color: kText), decoration: _dec(tr(lang, 'e.g. 022 (Others)', '例如：022（其他）', 'cth. 022 (Lain-lain)'))),

        // ── Digital certificate (on-device signing, required for production) ──
        label(tr(lang, 'DIGITAL CERTIFICATE', '数字证书', 'SIJIL DIGITAL')),
        _buildCertBox(lang),

        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _saving ? null : (widget.isPro ? _save : () => showSubSheet(context)),
          style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
          child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(widget.isPro
                ? tr(lang, 'Save', '保存', 'Simpan')
                : '🔒 ${tr(lang, 'Pro feature', 'Pro 功能', 'Ciri Pro')}'),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () => showConsolidatedSheet(context),
          icon: const Icon(Icons.merge_type, size: 18),
          style: OutlinedButton.styleFrom(foregroundColor: kText, side: BorderSide(color: kBorder)),
          label: Text(tr(lang, 'Consolidated e-Invoice (B2C)', '合并发票 (B2C)', 'e-Invois Disatukan (B2C)')),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          onPressed: () => showSelfBilledSheet(context),
          icon: const Icon(Icons.swap_horiz, size: 18),
          style: OutlinedButton.styleFrom(foregroundColor: kText, side: BorderSide(color: kBorder)),
          label: Text(tr(lang, 'Self-billed e-Invoice', '自开发票', 'e-Invois Layan Diri')),
        )),
      ]),
    );
  }
}
