import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../utils.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MONTHLY BUDGET (Phase 4 #20, Pro)
// Set a monthly limit per expense category; track spend vs budget for the month.
// ═══════════════════════════════════════════════════════════════════════════════

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override State<BudgetScreen> createState() => _BudgetState();
}

class _BudgetState extends State<BudgetScreen> {
  Map<String, double> _budgets = {};
  bool _loading = true;
  bool _saving = false;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final b = await context.read<AppState>().loadBudgets();
    if (mounted) setState(() { _budgets = Map.from(b); _loading = false; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final clean = Map<String, double>.fromEntries(
      _budgets.entries.where((e) => e.value > 0));
    await context.read<AppState>().saveBudgets(clean);
    if (mounted) {
      setState(() => _saving = false);
      final lang = context.read<AppState>().settings.lang;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(lang, 'Budget saved', '预算已保存', 'Bajet disimpan')),
        backgroundColor: kDark, behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;
    // Month spend per GL account (includes bill-based spend on the same account).
    final monthBal = app.computeBalances(app.thisMonthTxs);
    final cats = userExpenseCategories;

    double spentOf(TxCategory c) => (monthBal[drAccountOf(c)] ?? 0).clamp(0, double.infinity).toDouble();

    final totalBudget = _budgets.values.fold<double>(0, (s, v) => s + v);
    final totalSpent  = cats.fold<double>(0, (s, c) => s + spentOf(c));

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, '📅 Monthly Budget', '📅 月度预算', '📅 Bajet Bulanan')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '…' : tr(lang, 'Save', '保存', 'Simpan'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(tr(lang, 'Spent / Budget this month', '本月已用 / 预算', 'Dibelanja / Bajet bulan ini'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text('${fmtMYR(totalSpent)} / ${fmtMYR(totalBudget)}',
                    style: TextStyle(
                      color: totalBudget > 0 && totalSpent > totalBudget ? const Color(0xFFF87171) : const Color(0xFF4ADE80),
                      fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(
                  value: totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.0) : 0,
                  minHeight: 6, backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(
                    totalBudget > 0 && totalSpent > totalBudget ? const Color(0xFFF87171) : const Color(0xFF4ADE80)),
                )),
              ]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              child: Text(tr(lang, 'Set a monthly limit per category (blank = none)', '为每个支出分类设置月度上限（留空=不限）', 'Tetapkan had bulanan setiap kategori (kosong = tiada)'),
                style: const TextStyle(fontSize: 12, color: kMuted)),
            ),

            ...cats.map((c) {
              final spent  = spentOf(c);
              final budget = _budgets[c.id] ?? 0;
              final over   = budget > 0 && spent > budget;
              final pct    = budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: over ? kRedBd : kBorder), borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  Row(children: [
                    Text(c.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c.label(app.settings.lang),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText))),
                    SizedBox(
                      width: 96,
                      child: TextFormField(
                        initialValue: budget > 0 ? budget.toStringAsFixed(budget == budget.truncate() ? 0 : 2) : '',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.right,
                        onChanged: (v) => _budgets[c.id] = double.tryParse(v) ?? 0,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                        decoration: InputDecoration(
                          prefixText: 'RM ', hintText: '0',
                          isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: true, fillColor: kBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: kBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: kBorder)),
                        ),
                      ),
                    ),
                  ]),
                  if (budget > 0 || spent > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(
                      value: pct, minHeight: 5, backgroundColor: kBg,
                      valueColor: AlwaysStoppedAnimation(over ? kRed : c.color),
                    )),
                    const SizedBox(height: 4),
                    Align(alignment: Alignment.centerLeft, child: Text(
                      budget > 0
                        ? '${tr(lang, 'Spent', '已用', 'Dibelanja')} ${fmtMYR(spent)} / ${fmtMYR(budget)}${over ? tr(lang, ' · over!', ' · 超支!', ' · melebihi!') : ''}'
                        : '${tr(lang, 'Spent', '已用', 'Dibelanja')} ${fmtMYR(spent)}',
                      style: TextStyle(fontSize: 11, color: over ? kRed : kMuted, fontWeight: over ? FontWeight.w700 : FontWeight.normal))),
                  ],
                ]),
              );
            }),
            const SizedBox(height: 30),
          ]),
    );
  }
}
