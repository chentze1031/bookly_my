import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../state/app_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// ONBOARDING — 3-screen intro carousel shown ONCE on first launch.
// Gated by StorageKeys.onboardingSeen. Skippable. Trilingual (EN / 中文 / BM).
// ════════════════════════════════════════════════════════════════════════════

/// Wraps the app shell. On first launch shows [OnboardingScreen]; afterwards
/// (or once dismissed) renders [child] directly. Sits OUTSIDE the AuthGate so
/// the intro appears before the sign-in screen.
class OnboardingGate extends StatefulWidget {
  final Widget child;
  const OnboardingGate({super.key, required this.child});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _seen; // null = still loading the flag

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _seen = prefs.getBool(StorageKeys.onboardingSeen) ?? false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.onboardingSeen, true);
    if (!mounted) return;
    setState(() => _seen = true);
  }

  @override
  Widget build(BuildContext context) {
    // While reading the flag, show a neutral background to avoid a flash.
    if (_seen == null) return Scaffold(backgroundColor: kBg, body: const SizedBox.shrink());
    if (_seen == false) return OnboardingScreen(onDone: _finish);
    return widget.child;
  }
}

class _Slide {
  final String emoji;
  final String title;
  final String body;
  final Color tint;
  const _Slide(this.emoji, this.title, this.body, this.tint);
}

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  List<_Slide> _slides(String l) => [
    _Slide(
      '📒',
      tr(l, 'Bookkeeping made simple', '记账，简单几秒', 'Simpan kira-kira dengan mudah'),
      tr(l,
        'Record income and expenses in seconds, manage customers, suppliers and inventory — all in one place.',
        '几秒记录收入与支出，管理客户、供应商与库存 —— 全部集中在一处。',
        'Rekod pendapatan & perbelanjaan dalam beberapa saat, urus pelanggan, pembekal & inventori — semua di satu tempat.'),
      kBlue,
    ),
    _Slide(
      '🧾',
      tr(l, 'e-Invoice ready', '符合 e-Invoice 合规', 'Sedia e-Invois'),
      tr(l,
        'Create invoices and stay compliant with Malaysia\'s LHDN e-Invoice (MyInvois) — right from your phone.',
        '开具发票，符合马来西亚 LHDN e-Invoice（MyInvois）要求 —— 在手机上即可完成。',
        'Cipta invois dan kekal patuh e-Invois LHDN (MyInvois) Malaysia — terus dari telefon anda.'),
      kPro,
    ),
    _Slide(
      '📊',
      tr(l, 'Reports at a glance', '报表一目了然', 'Laporan sepintas lalu'),
      tr(l,
        'See profit, SST and cash flow instantly. Export backups and grow your business with confidence.',
        '即时查看利润、SST 与现金流。导出备份，安心经营生意。',
        'Lihat untung, SST & aliran tunai serta-merta. Eksport sandaran dan kembangkan perniagaan dengan yakin.'),
      kGreen,
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isLast => _page == 2;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final slides = _slides(lang);
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(tr(lang, 'Skip', '跳过', 'Langkau'),
                    style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _slideView(slides[i]),
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? kPro : kBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            // Next / Get started
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPro,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    if (_isLast) {
                      widget.onDone();
                    } else {
                      _ctrl.nextPage(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut);
                    }
                  },
                  child: Text(
                    _isLast
                        ? tr(lang, 'Get started', '开始使用', 'Mula sekarang')
                        : tr(lang, 'Next', '下一步', 'Seterusnya'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slideView(_Slide s) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 132,
          height: 132,
          decoration: BoxDecoration(
            color: s.tint.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(s.emoji, style: const TextStyle(fontSize: 60)),
        ),
        const SizedBox(height: 36),
        Text(s.title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
        const SizedBox(height: 14),
        Text(s.body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, height: 1.55, color: kMuted)),
      ],
    ),
  );
}
