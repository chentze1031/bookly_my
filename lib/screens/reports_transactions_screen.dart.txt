import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'sub_screen.dart';
import '../models.dart';

// ════════════════════════════════════════════════════════════════════════════
// TRANSACTIONS SCREEN
// ════════════════════════════════════════════════════════════════════════════
class TransactionsScreen extends StatefulWidget {
  final void Function(Transaction tx) onEdit;
  const TransactionsScreen({super.key, required this.onEdit});
  @override State<TransactionsScreen> createState() => _TxScreenState();
}

class _TxScreenState extends State<TransactionsScreen> {
  String _filter = 'all';
  String _search = '';
  String _month  = '';

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final sub  = context.watch<SubState>();
    final t    = L10n(app.settings.lang);
    final lang = app.settings.lang;
    final months = app.availableMonths;

    var visible = app.txs.where((tx) {
      // Always hide internal transfer entries (AR/AP phase-2 payments).
      // These are balance-sheet-only moves and should not appear in Records.
      if (tx.type == 'transfer') return false;
      if (_filter != 'all' && tx.type != _filter) return false;
      if (_month.isNotEmpty && !tx.date.startsWith(_month)) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final cat = findCat(tx.catId);
        if (!(tx.descEN.toLowerCase().contains(q) ||
              tx.descZH.contains(q) ||
              (cat?.label(lang) ?? '').toLowerCase().contains(q))) return false;
      }
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    final groups = <String, List<Transaction>>{};
    for (final tx in visible) (groups[tx.date] ??= []).add(tx);

    return Column(
      children: [
        // ── Filter bar ───────────────────────────────────────────────────
        Container(
          color: kSurface,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: [
            GestureDetector(

              child: TextField(
                readOnly: false,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: t.search,
                  hintStyle: const TextStyle(color: kMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: kMuted),
                  filled: true, fillColor: kBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kBorder, width: 1.5)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kBorder, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _FilterChip(label: t.all,      value: 'all',     current: _filter, onTap: () => setState(() => _filter = 'all')),
                const SizedBox(width: 8),
                _FilterChip(label: t.income,   value: 'income',  current: _filter, onTap: () => setState(() => _filter = 'income'),  activeColor: kGreen),
                const SizedBox(width: 8),
                _FilterChip(label: t.expenses, value: 'expense', current: _filter, onTap: () => setState(() => _filter = 'expense'), activeColor: kRed),
                if (months.isNotEmpty) ...[
                  Container(width: 1, height: 24, color: kBorder, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(99)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _month.isEmpty ? null : _month,
                        hint: Text(t.allTime, style: const TextStyle(fontSize: 12, color: kMuted)),
                        isDense: true,
                        items: [
                          DropdownMenuItem(value: '', child: Text(t.allTime, style: const TextStyle(fontSize: 12))),
                          ...months.map((m) => DropdownMenuItem(value: m,
                            child: Text(monthLabel(m, lang), style: const TextStyle(fontSize: 12)))),
                        ],
                        onChanged: (v) => setState(() => _month = v ?? ''),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),

        // ── List ─────────────────────────────────────────────────────────
        Expanded(
          child: visible.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('📭', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 10),
                Text(t.noTx, style: const TextStyle(color: kMuted, fontSize: 14)),
              ]))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: groups.entries.map((entry) {
                  final date   = entry.key;
                  final txList = entry.value;
                  final dayIn  = txList.where((tx) => tx.type == 'income').fold<double>(0, (s, tx) => s + tx.amountMYR);
                  final dayOut = txList.where((tx) => tx.type == 'expense').fold<double>(0, (s, tx) => s + tx.amountMYR);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(fmtDateFull(date, lang).toUpperCase(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: kMuted, letterSpacing: 0.5)),
                            Row(children: [
                              if (dayIn  > 0) Text('+${fmtShort(dayIn)} ',  style: const TextStyle(fontSize: 11, color: kGreen)),
                              if (dayOut > 0) Text('-${fmtShort(dayOut)}',  style: const TextStyle(fontSize: 11, color: kRed)),
                            ]),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: kSurface, border: Border.all(color: kBorder),
                          borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: txList.asMap().entries.map((e2) {
                            final tx  = e2.value;
                            final cat = findCat(tx.catId);
                            return GestureDetector(
                              onTap: () => widget.onEdit(tx),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  border: e2.key > 0 ? const Border(top: BorderSide(color: kBorder)) : null),
                                child: Row(children: [
                                  Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: (cat?.color ?? Colors.grey).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(11)),
                                    child: Center(child: Text(cat?.icon ?? '💰',
                                      style: const TextStyle(fontSize: 19)))),
                                  const SizedBox(width: 11),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(lang == 'zh' ? tx.descZH : tx.descEN,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13,
                                          fontWeight: FontWeight.w600, color: kText)),
                                      Row(children: [
                                        Text(cat?.label(lang) ?? tx.catId,
                                          style: const TextStyle(fontSize: 10, color: kMuted)),
                                        if (tx.origCurrency != 'MYR')
                                          _Tag(label: tx.origCurrency, bg: kBlueBg, color: kBlue),
                                        if (tx.sstMYR > 0)
                                          _Tag(label: 'SST', bg: kGoldBg, color: kGold),
                                      ]),
                                    ],
                                  )),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    AmountDisplay(amount: tx.amountMYR, isIncome: tx.type == 'income'),
                                    const Text('tap to edit', style: TextStyle(fontSize: 9, color: kMuted)),
                                  ]),
                                ]),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }).toList(),
              ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final VoidCallback onTap;
  final Color activeColor;
  const _FilterChip({required this.label, required this.value,
    required this.current, required this.onTap, this.activeColor = kDark});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: current == value ? activeColor : const Color(0xFFF5F4F0),
        borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(
        color: current == value ? Colors.white : kMuted,
        fontWeight: FontWeight.w700, fontSize: 12)),
    ),
  );
}

class _Tag extends StatelessWidget {
  final String label; final Color bg, color;
  const _Tag({required this.label, required this.bg, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// REPORTS SCREEN
// ════════════════════════════════════════════════════════════════════════════
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override State<ReportsScreen> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsScreen> {
  String _view  = 'pl';
  String _month = '';

  @override
  Widget build(BuildContext context) {
    final app    = context.watch<AppState>();
    final sub    = context.watch<SubState>();
    final t      = L10n(app.settings.lang);
    final lang   = app.settings.lang;
    final months = app.availableMonths;

    final filtered = (_month.isNotEmpty)
      ? app.txs.where((tx) => tx.date.startsWith(_month)).toList()
      : app.txs;

    final bal = app.computeBalances(filtered);
    double b(String k) => bal[k] ?? 0;

    final totalRev  = b('4010') + b('4020') + b('4030');
    final cogs      = b('5010');
    final grossP    = totalRev - cogs;
    final opCodes   = ['5100','5110','5120','5130','5140','5150','5160','5170','5180','5190','5200'];
    final totalOpEx = opCodes.fold<double>(0, (s, c) => s + b(c));
    final netInc    = grossP - totalOpEx;

    final allBal   = app.computeBalances();
    final cash     = allBal['1020'] ?? 0;
    final ar       = allBal['1100'] ?? 0;
    final inv      = allBal['1200'] ?? 0;
    final totalA   = cash + ar + inv;
    final ap       = allBal['2010'] ?? 0;
    final equity   = totalA - ap;

    final sstIn  = filtered.where((tx) => tx.type == 'income').fold<double>(0, (s, tx) => s + tx.sstMYR);
    final sstOut = filtered.where((tx) => tx.type == 'expense').fold<double>(0, (s, tx) => s + tx.sstMYR);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          // Month picker
          if (true)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _month.isEmpty ? null : _month,
                  hint: Text(t.allTime, style: const TextStyle(fontSize: 14, color: kMuted)),
                  items: [
                    DropdownMenuItem(value: '', child: Text(t.allTime, style: const TextStyle(fontSize: 14))),
                    ...months.map((m) => DropdownMenuItem(value: m,
                      child: Text(monthLabel(m, lang), style: const TextStyle(fontSize: 14)))),
                  ],
                  onChanged: (v) => setState(() => _month = v ?? ''),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => showSubSheet(context),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kProBg,
                  border: Border.all(color: kProBd, width: 1.5),
                  borderRadius: BorderRadius.circular(12)),
                child: Text('🔒 ${t.proLocked} — Monthly filter',
                  style: const TextStyle(color: kPro, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),

          // View toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              _ViewTab(label: t.pl,     value: 'pl',  current: _view, onTap: () => setState(() => _view = 'pl')),
              _ViewTab(label: t.bs,     value: 'bs',  current: _view, onTap: () => setState(() => _view = 'bs')),
              _ViewTab(
                label: t.sstRep,
                value: 'sst', current: _view,
                onTap: () => setState(() => _view = 'sst')),
            ]),
          ),
          const SizedBox(height: 14),

          // P&L
          if (_view == 'pl') _PLCard(t: t, lang: lang, b: b,
            totalRev: totalRev, cogs: cogs, grossP: grossP,
            totalOpEx: totalOpEx, netInc: netInc),

          // Balance Sheet
          if (_view == 'bs') _BSView(t: t,
            cash: cash, ar: ar, inv: inv, totalA: totalA,
            ap: ap, equity: equity),

          // SST Report
          if (_view == 'sst')
            _SSTView(t: t, sstIn: sstIn, sstOut: sstOut,
              reminder: t.reminder, sstRegNo: app.settings.sstRegNo),
        ],
      ),
    );
  }
}

class _ViewTab extends StatelessWidget {
  final String label, value, current; final VoidCallback onTap;
  const _ViewTab({required this.label, required this.value, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: current == value ? kDark : Colors.transparent,
          borderRadius: BorderRadius.circular(9)),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: current == value ? Colors.white : kMuted,
            fontWeight: FontWeight.w700, fontSize: 11)),
      ),
    ),
  );
}

// ── P&L ──────────────────────────────────────────────────────────────────────
class _PLCard extends StatelessWidget {
  final L10n t; final String lang;
  final double Function(String) b;
  final double totalRev, cogs, grossP, totalOpEx, netInc;
  const _PLCard({required this.t, required this.lang, required this.b,
    required this.totalRev, required this.cogs, required this.grossP,
    required this.totalOpEx, required this.netInc});

  @override
  Widget build(BuildContext context) {
    final opItems = [
      ('salary','5100'), ('rent','5110'), ('utilities','5120'), ('supplies','5130'),
      ('marketing','5140'), ('insurance','5150'), ('meals','5160'), ('travel','5170'),
      ('professional','5180'), ('repairs','5190'), ('cogs','5010'), ('other_expense','5200'),
    ].where((item) => b(item.$2) > 0).toList();

    return Container(
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        _SecHdr(label: t.pl),
        _SecLabel(label: t.revenue, color: kGreen, bgColor: kGreenBg),
        _Row(label: incomeCategories[0].label(lang), val: b('4010'), indent: true),
        _Row(label: incomeCategories[1].label(lang), val: b('4020'), indent: true),
        _Row(label: incomeCategories[3].label(lang), val: b('4030'), indent: true),
        _Row(label: t.totalRev,  val: totalRev, bold: true, color: kGreen, top: true),
        _Row(label: t.cogs,      val: cogs,     indent: true),
        _Row(label: t.grossP,    val: grossP,   bold: true, color: grossP >= 0 ? kGreen : kRed, top: true),
        _SecLabel(label: t.opex, color: kRed, bgColor: kRedBg),
        ...opItems.map((item) => _Row(
          label: findCat(item.$1)?.label(lang) ?? item.$1,
          val: b(item.$2), indent: true)),
        _Row(label: t.totalEx,   val: totalOpEx, bold: true, color: kRed, top: true),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          color: netInc >= 0 ? kGreenBg : kRedBg,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(t.netProfit, style: const TextStyle(fontWeight: FontWeight.w900,
              fontSize: 14, color: kText)),
            Text('${netInc >= 0 ? '+' : '-'}${fmtMYR(netInc.abs())}',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22,
                color: netInc >= 0 ? kGreen : kRed, fontFamily: 'Georgia')),
          ]),
        ),
      ]),
    );
  }
}

// ── Balance Sheet ─────────────────────────────────────────────────────────────
class _BSView extends StatelessWidget {
  final L10n t;
  final double cash, ar, inv, totalA, ap, equity;
  const _BSView({required this.t, required this.cash, required this.ar,
    required this.inv, required this.totalA, required this.ap, required this.equity});
  @override
  Widget build(BuildContext context) => Column(children: [
    _BSBlock(label: t.assets, total: totalA, color: kGreen, bgColor: kGreenBg,
      items: [(t.cashBank, cash), (t.ar, ar), (t.inventory, inv)]),
    const SizedBox(height: 10),
    _BSBlock(label: t.liab, total: ap, color: kRed, bgColor: kRedBg,
      items: [(t.ap, ap)]),
    const SizedBox(height: 10),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(t.equity, style: const TextStyle(color: Color(0xFF6B6860), fontSize: 13)),
        Text(fmtMYR(equity), style: TextStyle(
          fontWeight: FontWeight.w900, fontSize: 24, fontFamily: 'Georgia',
          color: equity >= 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171))),
      ]),
    ),
  ]);
}

class _BSBlock extends StatelessWidget {
  final String label; final double total; final Color color, bgColor;
  final List<(String, double)> items;
  const _BSBlock({required this.label, required this.total,
    required this.color, required this.bgColor, required this.items});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(16)),
    clipBehavior: Clip.hardEdge,
    child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: bgColor,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
          Text(fmtMYR(total), style: TextStyle(fontWeight: FontWeight.w900,
            fontSize: 16, color: color, fontFamily: 'Georgia')),
        ]),
      ),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.fromLTRB(26, 8, 14, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(item.$1, style: const TextStyle(fontSize: 12, color: kMuted)),
          Text(fmtMYR(item.$2), style: const TextStyle(fontSize: 12, fontFamily: 'Georgia', color: kText)),
        ]),
      )),
    ]),
  );
}

// ── SST Report ────────────────────────────────────────────────────────────────
class _SSTView extends StatelessWidget {
  final L10n t; final double sstIn, sstOut;
  final String reminder, sstRegNo;
  const _SSTView({required this.t, required this.sstIn, required this.sstOut,
    required this.reminder, required this.sstRegNo});
  @override
  Widget build(BuildContext context) {
    final net = sstIn - sstOut;
    return Column(children: [
      Row(children: [
        _SSTChip(label: t.sstCollected, val: sstIn,  color: kGreen),
        const SizedBox(width: 8),
        _SSTChip(label: t.sstPaid,      val: sstOut, color: kRed),
        const SizedBox(width: 8),
        _SSTChip(label: t.sstNet,       val: net,    color: net >= 0 ? kGreen : kRed),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: kGoldBg, border: Border.all(color: kGoldBd),
          borderRadius: BorderRadius.circular(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(reminder, style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
          if (sstRegNo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('SST Reg: $sstRegNo',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kGold)),
          ],
        ]),
      ),
    ]);
  }
}

class _SSTChip extends StatelessWidget {
  final String label; final double val; final Color color;
  const _SSTChip({required this.label, required this.val, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kMuted), textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(fmtMYR(val), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
          color: color, fontFamily: 'Georgia')),
      ]),
    ),
  );
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final String label; final double val;
  final bool indent, bold, top; final Color? color;
  const _Row({required this.label, required this.val,
    this.indent = false, this.bold = false, this.top = false, this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(indent ? 26 : 14, indent ? 8 : 10, 14, indent ? 8 : 10),
    decoration: BoxDecoration(
      border: top ? const Border(top: BorderSide(color: kBorder, width: 2)) : null,
      color: bold ? kBg : Colors.transparent),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: indent ? 12 : 14,
        fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
        color: indent ? kMuted : kText)),
      Text(fmtMYR(val), style: TextStyle(fontSize: bold ? 15 : 14,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: color ?? kText, fontFamily: 'Georgia')),
    ]),
  );
}

class _SecHdr extends StatelessWidget {
  final String label;
  const _SecHdr({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    color: kBg, width: double.infinity,
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800,
      fontSize: 14, color: kText)),
  );
}

class _SecLabel extends StatelessWidget {
  final String label; final Color color, bgColor;
  const _SecLabel({required this.label, required this.color, required this.bgColor});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 5, 14, 5),
    color: bgColor, width: double.infinity,
    child: Row(children: [
      Container(width: 4, height: 14, color: color, margin: const EdgeInsets.only(right: 8)),
      Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 0.5)),
    ]),
  );
}
