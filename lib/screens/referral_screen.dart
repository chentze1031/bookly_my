import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../services/referral_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// REFERRAL SCREEN (Settings → Invite friends)
//
// Shows the user's invite code (copy / share), referral progress, the reward
// tier table, and a field for referees to enter a friend's code.
// Reward (highest tier reached, granted as a RevenueCat promo on `pro`):
//   1 active referral → 7 days · 5 → 2 months · 10 → 6 months · 20 → 1 year.
// A referee only counts once they become ACTIVE (≥3 transactions).
// ════════════════════════════════════════════════════════════════════════════

// Tiers in ascending order: (referrals needed, reward duration label key).
const _tiers = [1, 5, 10, 20];

String _rewardLabel(String l, int tier) {
  switch (tier) {
    case 1:  return tr(l, '7 days Pro',    '7 天 Pro',  '7 hari Pro');
    case 5:  return tr(l, '2 months Pro',  '2 个月 Pro', '2 bulan Pro');
    case 10: return tr(l, '6 months Pro',  '6 个月 Pro', '6 bulan Pro');
    case 20: return tr(l, '1 year Pro',    '1 年 Pro',   '1 tahun Pro');
    default: return '';
  }
}

int _highestTier(int n) => n >= 20 ? 20 : n >= 10 ? 10 : n >= 5 ? 5 : n >= 1 ? 1 : 0;
int? _nextTier(int n) => _tiers.cast<int?>().firstWhere((t) => (t ?? 0) > n, orElse: () => null);

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  ReferralInfo? _info;
  bool _loading = true;
  bool _loadError = false;
  final _codeCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = false; });
    final info = await ReferralService.me();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loadError = info == null;
      _loading = false;
    });
  }

  String _shareText(String l, String code) {
    // The &referrer=ref%3DCODE param lets Google Play hand the code to the app
    // on install, so the friend is auto-credited (manual code entry is fallback).
    final link =
        'https://play.google.com/store/apps/details?id=com.bookly.my&referrer=ref%3D$code';
    return tr(l,
      'I\'m using Bookly MY to run my business accounting — invoices, e-Invoice (MyInvois), payroll & more. '
      'Install via my link (code $code is applied automatically):\n$link',
      '我在用 Bookly MY 管账——发票、电子发票（MyInvois）、薪资等一应俱全。'
      '点我的链接安装即可自动套用邀请码 $code：\n$link',
      'Saya guna Bookly MY untuk perakaunan perniagaan — invois, e-Invois (MyInvois), gaji & lain-lain. '
      'Pasang melalui pautan saya (kod $code digunakan automatik):\n$link');
  }

  Future<void> _copyCode(String l, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(l, 'Invite code copied', '邀请码已复制', 'Kod jemputan disalin')),
      backgroundColor: kDark, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _submit(String l) async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty || _submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submitting = true);
    final result = await ReferralService.submitCode(code);
    if (!mounted) return;
    setState(() => _submitting = false);
    final ok = result == 'ok';
    final msg = switch (result) {
      'ok'             => tr(l, 'Code applied! Your friend will be rewarded once you stay active.', '已应用邀请码！当你持续记账后，好友将获得奖励。', 'Kod digunakan! Rakan anda akan diberi ganjaran apabila anda aktif.'),
      'invalid_code'   => tr(l, 'Invalid code', '邀请码无效', 'Kod tidak sah'),
      'self_referral'  => tr(l, 'You can\'t use your own code', '不能使用自己的邀请码', 'Tidak boleh guna kod sendiri'),
      'already_linked' => tr(l, 'You\'ve already entered a code', '你已经输入过邀请码', 'Anda sudah masukkan kod'),
      'no_code'        => tr(l, 'Enter a code first', '请先输入邀请码', 'Masukkan kod dahulu'),
      _                => tr(l, 'Something went wrong, please try again', '出错了，请重试', 'Ralat, sila cuba lagi'),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? kGreen : kRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    if (ok) { _codeCtrl.clear(); await _load(); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final l = app.settings.lang;
    final loggedIn = app.currentUid != null;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(l, 'Invite Friends', '邀请好友', 'Jemput Rakan')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: !loggedIn
        ? _signInPrompt(l)
        : _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError
            ? _errorState(l)
            : _content(l, _info!),
    );
  }

  Widget _signInPrompt(String l) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        tr(l, 'Sign in to get your invite code and earn rewards.',
          '登录后即可获取邀请码并赚取奖励。',
          'Log masuk untuk dapatkan kod jemputan & ganjaran.'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: kMuted),
      ),
    ),
  );

  Widget _errorState(String l) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr(l, 'Couldn\'t load referrals.', '无法加载邀请信息。', 'Gagal memuatkan jemputan.'),
          style: const TextStyle(fontSize: 14, color: kMuted)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(tr(l, 'Retry', '重试', 'Cuba lagi')),
        ),
      ]),
    ),
  );

  Widget _content(String l, ReferralInfo info) {
    final valid = info.validReferrals;
    final reached = _highestTier(valid);
    final next = _nextTier(valid);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // ── Headline ─────────────────────────────────────────────────────
        Text(tr(l, 'Invite friends, earn free Pro', '邀请好友，免费得 Pro', 'Jemput rakan, dapat Pro percuma'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kText)),
        const SizedBox(height: 6),
        Text(tr(l,
          'Share your code. Each friend who installs Bookly and records at least 3 transactions counts as a valid referral. The more friends, the bigger your free Pro reward.',
          '分享你的邀请码。每位安装 Bookly 并记满 3 笔交易的好友算一次有效邀请。邀请越多，免费 Pro 奖励越大。',
          'Kongsi kod anda. Setiap rakan yang pasang Bookly & rekod sekurang-kurangnya 3 transaksi dikira jemputan sah. Lebih ramai rakan, lebih besar ganjaran Pro percuma anda.'),
          style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.5)),
        const SizedBox(height: 18),

        // ── Invite code card ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(l, 'YOUR INVITE CODE', '你的邀请码', 'KOD JEMPUTAN ANDA'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: Color(0xB3FFFFFF), letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Text(info.code,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 6, fontFamily: 'monospace'))),
              IconButton(
                onPressed: () => _copyCode(l, info.code),
                icon: const Icon(Icons.copy_rounded, color: Colors.white, size: 22),
                tooltip: tr(l, 'Copy', '复制', 'Salin'),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () => Share.share(_shareText(l, info.code)),
              icon: const Icon(Icons.share, size: 18),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: const Color(0xFF1E0A3C),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              label: Text(tr(l, 'Share invite', '分享邀请', 'Kongsi jemputan'),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            )),
          ]),
        ),
        const SizedBox(height: 18),

        // ── Progress ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: kSurface, border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$valid',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: kText)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(tr(l, 'valid referral${valid == 1 ? '' : 's'}', '位有效邀请', 'jemputan sah'),
                  style: const TextStyle(fontSize: 13, color: kMuted)),
              ),
            ]),
            const SizedBox(height: 6),
            if (reached > 0)
              Text('🎁 ${tr(l, 'Current reward', '当前奖励', 'Ganjaran semasa')}: ${_rewardLabel(l, reached)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kGreen)),
            if (next != null) ...[
              const SizedBox(height: 8),
              Text(tr(l,
                '${next - valid} more to unlock ${_rewardLabel(l, next)}',
                '再邀请 ${next - valid} 位即可解锁 ${_rewardLabel(l, next)}',
                '${next - valid} lagi untuk buka ${_rewardLabel(l, next)}'),
                style: const TextStyle(fontSize: 12.5, color: kMuted)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (valid / next).clamp(0.0, 1.0),
                  minHeight: 8, backgroundColor: kBorder,
                  valueColor: AlwaysStoppedAnimation(kPro),
                ),
              ),
            ] else if (reached == 20) ...[
              const SizedBox(height: 8),
              Text(tr(l, 'You\'ve reached the top reward — thank you! 🎉',
                '你已达到最高奖励——感谢支持！🎉',
                'Anda capai ganjaran tertinggi — terima kasih! 🎉'),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPro)),
            ],
          ]),
        ),
        const SizedBox(height: 18),

        // ── Reward tiers table ───────────────────────────────────────────
        Text(tr(l, 'REWARD TIERS', '奖励阶梯', 'TAHAP GANJARAN'),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: .5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: kSurface, border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            for (int i = 0; i < _tiers.length; i++) ...[
              if (i > 0) Divider(height: 1, color: kBorder),
              _tierRow(l, _tiers[i], valid),
            ],
          ]),
        ),
        const SizedBox(height: 22),

        // ── Referee: enter a friend's code ───────────────────────────────
        if (info.isReferred)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kGreenBg, border: Border.all(color: kGreenBd),
              borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.check_circle, color: kGreen, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(tr(l,
                'You joined with a friend\'s invite code. Keep recording transactions so they get rewarded!',
                '你已通过好友的邀请码加入。继续记账，好友就能获得奖励！',
                'Anda sertai dengan kod rakan. Teruskan rekod transaksi supaya mereka diberi ganjaran!'),
                style: TextStyle(fontSize: 12.5, color: kText, height: 1.4))),
            ]),
          )
        else ...[
          Text(tr(l, 'HAVE A FRIEND\'S CODE?', '有好友的邀请码？', 'ADA KOD RAKAN?'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: .5)),
          const SizedBox(height: 8),
          Text(tr(l,
            'Enter it once to credit the friend who invited you. You can only do this before you become active.',
            '输入一次，即可让邀请你的好友获得奖励积分。只能在你成为活跃用户前输入。',
            'Masukkan sekali untuk kreditkan rakan yang menjemput anda. Hanya boleh sebelum anda menjadi aktif.'),
            style: const TextStyle(fontSize: 12, color: kMuted, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: TextStyle(fontSize: 16, color: kText, letterSpacing: 3, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                counterText: '',
                hintText: tr(l, 'ABC123', 'ABC123', 'ABC123'),
                hintStyle: const TextStyle(color: kMuted, letterSpacing: 3),
                filled: true, fillColor: kSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kBorder)),
              ),
              onSubmitted: (_) => _submit(l),
            )),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _submitting ? null : () => _submit(l),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(tr(l, 'Apply', '应用', 'Guna'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _tierRow(String l, int tier, int valid) {
    final done = valid >= tier;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(children: [
        Container(
          width: 34, height: 34, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? kGreenBg : kBg,
            border: Border.all(color: done ? kGreenBd : kBorder),
            borderRadius: BorderRadius.circular(99)),
          child: done
            ? Icon(Icons.check, size: 18, color: kGreen)
            : Text('$tier', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kText)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(
          tr(l, '$tier valid referral${tier == 1 ? '' : 's'}', '$tier 位有效邀请', '$tier jemputan sah'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText))),
        Text(_rewardLabel(l, tier),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: done ? kGreen : kPro)),
      ]),
    );
  }
}
