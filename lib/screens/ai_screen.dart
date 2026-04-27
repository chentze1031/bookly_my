import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../screens/sub_screen.dart';
import '../services/ai_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// AI SCREEN — tab with two sections: Auto-Cat + Cash Flow Forecast
// ════════════════════════════════════════════════════════════════════════════
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});
  @override State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubState>();
    if (!sub.isPro) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(title: const Text('✨  AI Assistant')),
        body: const _ProGate(),
      );
    }
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Row(children: [
          const Text('✨', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Text('AI Assistant'),
        ]),
        bottom: TabBar(
          controller: _tabs,
          labelColor: kText,
          unselectedLabelColor: kMuted,
          indicatorColor: kDark,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: '🏷️  Auto-Category'),
            Tab(text: '📈  Cash Flow'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _AutoCatTab(),
          _CashflowTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 1 — AUTO-CATEGORISE
// ════════════════════════════════════════════════════════════════════════════
class _AutoCatTab extends StatefulWidget {
  const _AutoCatTab();
  @override State<_AutoCatTab> createState() => _AutoCatTabState();
}

class _AutoCatTabState extends State<_AutoCatTab> {
  final _descCtrl = TextEditingController();
  final _amtCtrl  = TextEditingController();
  String _type    = 'expense';
  bool   _loading = false;
  AutoCatResult? _result;
  String? _error;
  TxCategory? _matchedCat;

  Future<void> _analyse() async {
    final desc = _descCtrl.text.trim();
    final amt  = double.tryParse(_amtCtrl.text) ?? 0;
    if (desc.isEmpty || amt <= 0) {
      setState(() => _error = 'Please enter description and amount.');
      return;
    }

    setState(() { _loading = true; _result = null; _error = null; _matchedCat = null; });

    try {
      final cats   = _type == 'income' ? incomeCategories : expenseCategories;
      final ids    = cats.map((c) => c.id).toList();
      final labels = { for (var c in cats) c.id: c.enLabel };

      final result = await AiService.categorise(
        description:     desc,
        type:            _type,
        amount:          amt,
        categoryIds:     ids,
        categoryLabels:  labels,
      );

      final matched = cats.firstWhere(
        (c) => c.id == result.catId,
        orElse: () => cats.first,
      );

      setState(() { _result = result; _matchedCat = matched; });
    } catch (e) {
      setState(() => _error = 'AI error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // Apply result — opens AddTxSheet with pre-filled category
  void _apply() {
    if (_matchedCat == null) return;
    Navigator.pop(context, _matchedCat);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Explainer ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCDD7FF)),
            ),
            child: Row(children: [
              const Text('🤖', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(child: Text(
                'Describe your transaction and Claude AI will suggest the best category for you.',
                style: TextStyle(fontSize: 13, color: Color(0xFF3344AA)),
              )),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Type toggle ────────────────────────────────────────────────
          const Text('TRANSACTION TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Row(children: [
            _TypePill(label: '📥 Income',  active: _type == 'income',  onTap: () => setState(() { _type = 'income';  _result = null; })),
            const SizedBox(width: 10),
            _TypePill(label: '📤 Expense', active: _type == 'expense', onTap: () => setState(() { _type = 'expense'; _result = null; })),
          ]),
          const SizedBox(height: 16),

          // ── Description ────────────────────────────────────────────────
          const Text('DESCRIPTION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              hintText: 'e.g. Grab Food delivery, TNB electric bill...',
              hintStyle: const TextStyle(color: kMuted, fontSize: 13),
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDark, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 14),

          // ── Amount ─────────────────────────────────────────────────────
          const Text('AMOUNT (MYR)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          TextField(
            controller: _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              prefixText: 'RM ',
              prefixStyle: const TextStyle(color: kText, fontWeight: FontWeight.w700),
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDark, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),

          // ── Analyse button ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _loading ? null : _analyse,
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('✨ Analyse with AI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),

          // ── Error ──────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kRedBd)),
              child: Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
            ),
          ],

          // ── Result card ────────────────────────────────────────────────
          if (_result != null && _matchedCat != null) ...[
            const SizedBox(height: 20),
            _ResultCard(result: _result!, cat: _matchedCat!, lang: app.settings.lang),
          ],
        ],
      ),
    );
  }
}

// ── Result Card ─────────────────────────────────────────────────────────────
class _ResultCard extends StatelessWidget {
  final AutoCatResult result;
  final TxCategory cat;
  final String lang;
  const _ResultCard({required this.result, required this.cat, required this.lang});

  @override
  Widget build(BuildContext context) {
    final pct = (result.confidence * 100).round();
    final Color confColor = pct >= 80 ? kGreen : pct >= 50 ? Colors.orange : kRed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('✅', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          const Text('AI Suggestion', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: confColor.withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
            child: Text('$pct% match', style: TextStyle(color: confColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(color: kBorder, height: 1),
        const SizedBox(height: 14),

        // Category display
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: cat.color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(cat.icon, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(cat.label(lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
            Text(cat.enLabel, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ]),

        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(result.reason, style: const TextStyle(fontSize: 13, color: kMuted))),
          ]),
        ),

        // Confidence bar
        const SizedBox(height: 14),
        Row(children: [
          const Text('Confidence', style: TextStyle(fontSize: 12, color: kMuted)),
          const Spacer(),
          Text('$pct%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: confColor)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: result.confidence,
            minHeight: 6,
            backgroundColor: kBorder,
            valueColor: AlwaysStoppedAnimation<Color>(confColor),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 2 — CASH FLOW FORECAST
// ════════════════════════════════════════════════════════════════════════════
class _CashflowTab extends StatefulWidget {
  const _CashflowTab();
  @override State<_CashflowTab> createState() => _CashflowTabState();
}

class _CashflowTabState extends State<_CashflowTab> {
  bool _loading  = false;
  bool _hasLoaded = false;
  CashflowForecast? _forecast;
  List<MonthSummary>? _history;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final txs = app.txs;
    if (txs.isEmpty) {
      setState(() { _error = 'No transactions yet. Add some records first.'; _hasLoaded = true; });
      return;
    }

    // Build last 6 months of summaries from existing transactions
    final now    = DateTime.now();
    final months = <MonthSummary>[];
    for (int i = 5; i >= 0; i--) {
      final m   = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM yyyy').format(m);
      double inc = 0, exp = 0;
      for (final tx in txs) {
        final d = DateTime.tryParse(tx.date);
        if (d == null) continue;
        if (d.year == m.year && d.month == m.month) {
          if (tx.type == 'income')  inc += tx.amountMYR;
          if (tx.type == 'expense') exp += tx.amountMYR;
        }
      }
      months.add(MonthSummary(label: key, income: inc, expense: exp));
    }

    setState(() { _loading = true; _error = null; _history = months; });

    try {
      final result = await AiService.forecast(history: months, currency: 'MYR');
      setState(() { _forecast = result; _hasLoaded = true; });
    } catch (e) {
      setState(() { _error = 'AI error: $e'; _hasLoaded = true; });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: kDark, strokeWidth: 2),
          SizedBox(height: 16),
          Text('Claude AI is analysing your finances...', style: TextStyle(color: kMuted, fontSize: 13)),
        ],
      ));
    }

    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('😕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 14)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: _load, style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
            child: const Text('Retry')),
        ]),
      ));
    }

    if (_forecast == null) return const SizedBox.shrink();

    final fc = _forecast!;
    final hist = _history ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      color: kDark,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Trend badge ────────────────────────────────────────────
            _TrendBanner(trend: fc.trend),
            const SizedBox(height: 16),

            // ── Alert ──────────────────────────────────────────────────
            if (fc.alert != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: kRedBd)),
                child: Row(children: [
                  const Text('⚠️', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(fc.alert!, style: const TextStyle(color: kRed, fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── History chart ──────────────────────────────────────────
            const Text('PAST 6 MONTHS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
            const SizedBox(height: 12),
            _BarChart(months: hist, isForecast: false),
            const SizedBox(height: 20),

            // ── Forecast chart ─────────────────────────────────────────
            const Text('AI FORECAST — NEXT 3 MONTHS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
            const SizedBox(height: 12),
            _BarChart(months: fc.forecast, isForecast: true),
            const SizedBox(height: 20),

            // ── Forecast numbers ───────────────────────────────────────
            ...fc.forecast.map((m) => _ForecastRow(month: m)),
            const SizedBox(height: 20),

            // ── AI Insights ────────────────────────────────────────────
            const Text('AI INSIGHTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
            const SizedBox(height: 10),
            ...fc.insights.asMap().entries.map((e) => _InsightTile(index: e.key + 1, text: e.value)),

            const SizedBox(height: 12),
            Center(child: Text('Pull down to refresh forecast', style: TextStyle(fontSize: 11, color: kMuted.withOpacity(0.6)))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Mini bar chart (pure Flutter, no package needed) ────────────────────────
class _BarChart extends StatelessWidget {
  final List<MonthSummary> months;
  final bool isForecast;
  const _BarChart({required this.months, required this.isForecast});

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
    final maxVal = months.fold<double>(0, (m, s) => [m, s.income, s.expense].reduce((a, b) => a > b ? a : b));
    if (maxVal == 0) return const Center(child: Text('No data', style: TextStyle(color: kMuted)));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: months.map((m) {
                final incH = maxVal > 0 ? (m.income  / maxVal * 90) : 0.0;
                final expH = maxVal > 0 ? (m.expense / maxVal * 90) : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _Bar(height: incH,  color: isForecast ? kGreen.withOpacity(0.5) : kGreen),
                            const SizedBox(width: 2),
                            _Bar(height: expH,  color: isForecast ? kRed.withOpacity(0.5)   : kRed),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m.label.length > 6 ? m.label.substring(0, 3) : m.label,
                          style: const TextStyle(fontSize: 9, color: kMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _Legend(color: kGreen, label: 'Income'),
            const SizedBox(width: 16),
            _Legend(color: kRed,   label: 'Expense'),
          ]),
          if (isForecast)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Lighter bars = AI forecast', style: TextStyle(fontSize: 10, color: kMuted)),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;
  const _Bar({required this.height, required this.color});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    width: 10,
    height: height.clamp(2, 90),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
  );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 11, color: kMuted)),
  ]);
}

// ── Forecast row ─────────────────────────────────────────────────────────────
class _ForecastRow extends StatelessWidget {
  final MonthSummary month;
  const _ForecastRow({required this.month});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final netPos = month.net >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('🔮 ${month.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: netPos ? kGreenBg : kRedBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '${netPos ? '+' : ''}RM ${fmt.format(month.net)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: netPos ? kGreen : kRed),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _MiniStat(label: 'Income',  value: 'RM ${fmt.format(month.income)}',  color: kGreen)),
          const SizedBox(width: 10),
          Expanded(child: _MiniStat(label: 'Expense', value: 'RM ${fmt.format(month.expense)}', color: kRed)),
        ]),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value,  style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w800)),
    ]),
  );
}

// ── Trend banner ─────────────────────────────────────────────────────────────
class _TrendBanner extends StatelessWidget {
  final String trend;
  const _TrendBanner({required this.trend});

  @override
  Widget build(BuildContext context) {
    final map = {
      'growing':  (icon: '📈', label: 'Growing',  color: kGreen,        bg: kGreenBg, bd: kGreenBd),
      'stable':   (icon: '➡️', label: 'Stable',   color: Colors.orange, bg: const Color(0xFFFFF3E0), bd: const Color(0xFFFFCC80)),
      'declining':(icon: '📉', label: 'Declining', color: kRed,          bg: kRedBg,   bd: kRedBd),
    };
    final t = map[trend] ?? map['stable']!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: t.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.bd)),
      child: Row(children: [
        Text(t.icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Business Trend', style: TextStyle(fontSize: 11, color: t.color)),
          Text(t.label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: t.color)),
        ]),
      ]),
    );
  }
}

// ── Insight tile ──────────────────────────────────────────────────────────────
class _InsightTile extends StatelessWidget {
  final int index;
  final String text;
  const _InsightTile({required this.index, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(99)),
        child: Center(child: Text('$index', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: kText))),
    ]),
  );
}

// ── Type pill ─────────────────────────────────────────────────────────────────
class _TypePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TypePill({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color:  active ? kDark : kSurface,
        border: Border.all(color: active ? kDark : kBorder, width: 1.5),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700,
        color: active ? Colors.white : kMuted,
      )),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// PRO GATE — shown when feature requires subscription
// ════════════════════════════════════════════════════════════════════════════
class _ProGate extends StatelessWidget {
  const _ProGate();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: Text('✦', style: TextStyle(fontSize: 36, color: Colors.white))),
            ),
            const SizedBox(height: 24),
            const Text('Pro Feature', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kText)),
            const SizedBox(height: 10),
            const Text(
              'This feature is available for Pro subscribers.\nUpgrade to unlock AI-powered tools.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kMuted, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () => showSubSheet(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E0A3C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

