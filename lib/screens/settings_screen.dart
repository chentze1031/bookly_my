import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'company_info_screen.dart';
import 'sub_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// SETTINGS SCREEN
// ════════════════════════════════════════════════════════════════════════════
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

    void upd(AppSettings ns) => app.updateSettings(ns);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
      children: [

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
              s.companyName.isNotEmpty
                ? s.companyName
                : (t.isZh ? '未设置' : 'Not set'),
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                color: s.companyName.isNotEmpty ? kText : kMuted,
              ),
            ),
            subtitle: Text(
              s.coPhone.isNotEmpty
                ? s.coPhone
                : (t.isZh ? '点击编辑公司资料' : 'Tap to edit company info'),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
            trailing: const Icon(Icons.chevron_right, color: kMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CompanyInfoScreen())),
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
                      color: kBg,
                      border: Border.all(color: kBorder),
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
              onTap: () => _showComingSoon(context),
            ),
            const Divider(height: 1, color: kBorder, indent: 16),
            ListTile(
              leading: const Text('🏦', style: TextStyle(fontSize: 22)),
              title: const Text('Bank Statement Import',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Import PDF bank statement via AI',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => _showComingSoon(context),
            ),
            const Divider(height: 1, color: kBorder, indent: 16),
            ListTile(
              leading: const Text('📦', style: TextStyle(fontSize: 22)),
              title: const Text('Inventory',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Manage stock, prices & alerts',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => _showComingSoon(context),
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

  void _showComingSoon(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('🚧 Coming Soon'),
        content: const Text(
            'This feature is under development.\nStay tuned for updates!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _ProBlock extends StatelessWidget {
  final SubState sub;
  final L10n t;
  const _ProBlock({required this.sub, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
          colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('✦', style: TextStyle(fontSize: 24, color: Colors.white)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.proTitle, style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(t.monthly, style: const TextStyle(
              fontSize: 12, color: Color(0x99FFFFFF))),
        ]),
        const Spacer(),
        const ProBadge(),
      ]),
      if (sub.proExpires != null) ...[
        const SizedBox(height: 8),
        Text('${t.proExpires}: ${sub.proExpires}',
            style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
      ],
      const SizedBox(height: 10),
      Text(t.manageSub, style: const TextStyle(
          color: Color(0x80FFFFFF), fontSize: 12,
          decoration: TextDecoration.underline)),
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
            app.fxStatus == FxStatus.loading
              ? '⏳ Fetching…'
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

class _ExportBtn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _ExportBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Text(icon, style: const TextStyle(fontSize: 18)),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: const BorderSide(color: kBorder),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
  );
}

extension on L10n {
  String get proExpires => isZh ? '到期时间' : 'Expires';
}
