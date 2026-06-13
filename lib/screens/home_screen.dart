import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import '../constants.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'quotation_screen.dart';
import 'sub_screen.dart' show showSubSheet;

// ── 横幅广告ID ────────────────────────────────────────────────────────────────
const _admobBanner = 'ca-app-pub-1544282175684415/4562575468';

class HomeScreen extends StatelessWidget {
  final VoidCallback onAddIncome;
  final VoidCallback onAddExpense;
  final VoidCallback onInvoice;
  final VoidCallback onBill;
  final VoidCallback onPayroll;

  const HomeScreen({
    super.key,
    required this.onAddIncome,
    required this.onAddExpense,
    required this.onInvoice,
    required this.onBill,
    required this.onPayroll,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sub = context.watch<SubState>();
    final t   = L10n(app.settings.lang);
    final lang = app.settings.lang;

    final curMonth = app.currentMonth;
    final moTxs   = app.thisMonthTxs;
    final totalIn  = moTxs.where((tx) => tx.type == 'income').fold<double>(0, (s,tx)=>s+tx.amountMYR);
    final totalOut = moTxs.where((tx) => tx.type == 'expense').fold<double>(0, (s,tx)=>s+tx.amountMYR);
    final net      = totalIn - totalOut;

    // Top spending categories
    final expCats = expenseCategories.map((c) {
      final tot = moTxs.where((tx) => tx.catId == c.id).fold<double>(0,(s,tx)=>s+tx.amountMYR);
      return (cat: c, total: tot);
    }).where((e) => e.total > 0).toList()
      ..sort((a,b) => b.total.compareTo(a.total));
    final top = expCats.take(4).toList();
    final maxTop = top.isNotEmpty ? top.first.total : 1.0;

    final recent = [...app.txs]..sort((a,b) => b.date.compareTo(a.date));
    final recentFew = recent.take(4).toList();

    final co = app.settings.companyName.isNotEmpty
      ? app.settings.companyName
      : (lang == 'zh' ? '我的公司' : 'My Company');

    return Column(
      children: [
        // ── 页面内容 ────────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── Hero ───────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                  decoration: const BoxDecoration(
                    color: kDark,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(co, style: const TextStyle(color: Color(0xFF6B6860), fontSize: 12)),
                            // ── Date range selector (Task 3) ─────────────────
                            GestureDetector(
                              onTap: () => _showDateRangePicker(context, app, lang),
                              child: Row(children: [
                                Text(
                                  app.hasCustomRange
                                    ? app.dateRangeLabel
                                    : monthLabel(curMonth, lang),
                                  style: const TextStyle(color: Color(0xFF4B4840), fontSize: 11)),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4B4840), size: 14),
                                if (app.hasCustomRange) ...[
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => app.clearDateRange(),
                                    child: const Icon(Icons.close, color: Color(0xFF6B6860), size: 12),
                                  ),
                                ],
                              ]),
                            ),
                          ]),
                          Row(children: [
                            // ── Sync status indicator (Task 4) ──────────────
                            _SyncChip(status: app.syncStatus, pendingOps: app.pendingOps),
                            if (sub.isPro) ...[const SizedBox(width: 8), const ProBadge()],
                          ]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${net >= 0 ? '+' : '-'}${fmtShort(net.abs())}',
                        style: TextStyle(
                          color: net >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171),
                          fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -2,
                          fontFamily: 'Georgia',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(t.netProfit,
                        style: const TextStyle(color: Color(0xFF6B6860), fontSize: 11)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: _HeroCard(label: t.income,   value: totalIn,  sign: '+', color: const Color(0xFF4ADE80), bg: Color(0x1A4ADE80))),
                        const SizedBox(width: 10),
                        Expanded(child: _HeroCard(label: t.expenses, value: totalOut, sign: '-', color: const Color(0xFFF87171), bg: Color(0x1AF87171))),
                      ]),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // ── Quick actions ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    SizedBox(width: 68, child: _QuickBtn(icon:'📥', label:t.addIncome,  color:kGreen, bg:kGreenBg, bd:kGreenBd, onTap: onAddIncome)),
                    const SizedBox(width: 8),
                    SizedBox(width: 68, child: _QuickBtn(icon:'📤', label:t.addExpense, color:kRed,   bg:kRedBg,   bd:kRedBd,   onTap: onAddExpense)),
                    const SizedBox(width: 8),
                    SizedBox(width: 68, child: _QuickBtn(icon:'🧾', label: lang=='zh'?'发票':'Invoice', color:kMuted, bg:kBg, bd:kBorder, onTap: onInvoice)),
                    const SizedBox(width: 8),
                    SizedBox(width: 68, child: _QuickBtn(
                      icon:'📋', label: lang=='zh'?'报价单':'Quotation', color:kMuted, bg:kBg, bd:kBorder,
                      onTap: () {
                        if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => const QuotationHistoryScreen()));
                      },
                    )),
                    const SizedBox(width: 8),
                    SizedBox(width: 68, child: _QuickBtn(icon:'📄', label: lang=='zh'?'账单':'Bill', color:kMuted, bg:kBg, bd:kBorder, onTap: onBill)),
                    const SizedBox(width: 8),
                    SizedBox(width: 68, child: _QuickBtn(icon:'💼', label: lang=='zh'?'薪资':'Payslip', color:kMuted, bg:kBg, bd:kBorder, onTap: onPayroll)),
                  ]),
                ),
                ),
                const SizedBox(height: 14),

                // ── History shortcuts ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _HistoryBtn(
                          icon: '🧾',
                          label: lang == 'zh' ? '发票记录' : 'Invoice History',
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen())),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _HistoryBtn(
                          icon: '📋',
                          label: lang == 'zh' ? '报价单记录' : 'Quotation History',
                          onTap: () {
                            if (!context.read<SubState>().isPro) { showSubSheet(context); return; }
                            Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const QuotationHistoryScreen()));
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: _HistoryBtn(
                          icon: '💼',
                          label: lang == 'zh' ? '薪资记录' : 'Payroll History',
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PayrollHistoryScreen())),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: SizedBox()),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),

                // ── Top Spending ──────────────────────────────────────────
                if (top.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.topSpend, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
                          const SizedBox(height: 12),
                          ...top.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${e.cat.icon} ${e.cat.label(lang)}', style: const TextStyle(fontSize: 13, color: kText)),
                                  Text('-${fmtShort(e.total)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kRed)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: e.total / maxTop,
                                  minHeight: 5,
                                  backgroundColor: kBg,
                                  valueColor: AlwaysStoppedAnimation(e.cat.color),
                                ),
                              ),
                            ]),
                          )),
                        ],
                      ),
                    ),
                  ),

                // ── Recent ────────────────────────────────────────────────
                if (recentFew.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
                            child: Text(t.recent, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
                          ),
                          ...recentFew.asMap().entries.map((e) {
                            final tx = e.value;
                            final cat = findCat(tx.catId);
                            return Container(
                              decoration: BoxDecoration(
                                border: e.key > 0 ? const Border(top: BorderSide(color: kBorder)) : null,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(children: [
                                Container(
                                  width: 38, height: 38,
                                  decoration: BoxDecoration(
                                    color: (cat?.color ?? Colors.grey).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(child: Text(cat?.icon ?? '💰', style: const TextStyle(fontSize: 17))),
                                ),
                                const SizedBox(width: 11),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(lang == 'zh' ? tx.descZH : tx.descEN,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                                  Text(fmtDate(tx.date, lang),
                                    style: const TextStyle(fontSize: 11, color: kMuted)),
                                ])),
                                AmountDisplay(amount: tx.amountMYR, isIncome: tx.type == 'income'),
                              ]),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── 横幅广告（非Pro用户显示）─────────────────────────────────────────
        if (!sub.isPro) const _BannerAdWidget(),
      ],
    );
  }
}

// ── 横幅广告组件 ───────────────────────────────────────────────────────────────
class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    BannerAd(
      adUnitId: _admobBanner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    ).load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

// ── Date range picker helper (Task 3) ─────────────────────────────────────────
Future<void> _showDateRangePicker(BuildContext context, AppState app, String lang) async {
  final now = DateTime.now();
  final initial = DateTimeRange(
    start: app.filterFrom ?? DateTime(now.year, now.month, 1),
    end:   app.filterTo   ?? DateTime(now.year, now.month + 1, 0),
  );
  final picked = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate:  DateTime(now.year + 1, 12, 31),
    initialDateRange: initial,
    builder: (ctx, child) => Theme(
      data: ThemeData.light().copyWith(
        colorScheme: const ColorScheme.light(primary: Color(0xFF1A1A1A), onPrimary: Colors.white),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF1A1A1A)),
        ),
      ),
      child: child!,
    ),
  );
  if (picked != null) {
    app.setDateRange(picked.start, picked.end);
  }
}

// ── Sync status chip (Task 4) ─────────────────────────────────────────────────
class _SyncChip extends StatelessWidget {
  final SyncStatus status;
  final int pendingOps;
  const _SyncChip({required this.status, required this.pendingOps});

  @override
  Widget build(BuildContext context) {
    if (status == SyncStatus.idle && pendingOps == 0) return const SizedBox.shrink();

    final (icon, label, color) = switch (status) {
      SyncStatus.pulling || SyncStatus.pushing => (Icons.sync, 'Syncing…', const Color(0xFF60A5FA)),
      SyncStatus.done    => (Icons.cloud_done_outlined, 'Synced', const Color(0xFF4ADE80)),
      SyncStatus.error   => (Icons.cloud_off_outlined, 'Offline', const Color(0xFFF87171)),
      SyncStatus.idle    => pendingOps > 0
          ? (Icons.upload_outlined, '$pendingOps pending', const Color(0xFFFBBF24))
          : (Icons.cloud_done_outlined, 'Synced', const Color(0xFF4ADE80)),
    };

    final isAnimating = status == SyncStatus.pulling || status == SyncStatus.pushing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        isAnimating
          ? SizedBox(width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color))
          : Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ── 以下组件不变 ───────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String label; final double value; final String sign; final Color color; final Color bg;
  const _HeroCard({required this.label, required this.value, required this.sign, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF6B6860), fontSize: 11)),
      const SizedBox(height: 2),
      Text('$sign${fmtShort(value)}',
        style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'Georgia')),
    ]),
  );
}

class _QuickBtn extends StatelessWidget {
  final String icon, label; final Color color, bg, bd;
  final VoidCallback onTap; final bool pro;
  const _QuickBtn({required this.icon, required this.label, required this.color,
    required this.bg, required this.bd, required this.onTap, this.pro = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(color: bg, border: Border.all(color: bd, width: 2), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              SizedBox(
                width: 28, height: 28,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(icon),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: color)),
            ]),
          ),
          if (pro)
            Positioned(
              top: -6, right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFA855F7)]),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }

class _HistoryBtn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _HistoryBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kText),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Icon(Icons.chevron_right, size: 16, color: kMuted),
      ]),
    ),
  );
}
