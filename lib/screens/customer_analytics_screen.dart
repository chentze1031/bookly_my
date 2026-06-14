import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../utils.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER SPENDING ANALYTICS (Phase 2 Task #10, Pro)
//
// Aggregates saved invoices per customer: total spend, order count, average
// order value, first/last purchase, and the items they buy most.
// ═══════════════════════════════════════════════════════════════════════════════

class CustomerAnalyticsScreen extends StatefulWidget {
  const CustomerAnalyticsScreen({super.key});
  @override State<CustomerAnalyticsScreen> createState() => _CustomerAnalyticsState();
}

class _CustomerAnalyticsState extends State<CustomerAnalyticsScreen> {
  List<_CustStat> _stats = [];
  double _totalRevenue = 0;
  int    _orderCount = 0;
  bool   _loading = true;

  @override void initState() { super.initState(); _load(); }

  static double _invTotal(Map<String, dynamic> inv) {
    const sstMap = {'sst5':0.05,'sst10':0.10,'service6':0.06,'service8':0.08};
    return (inv['items'] as List? ?? []).fold<double>(0, (s, r) {
      final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
      final price = double.tryParse(r['price'] ?? '0') ?? 0;
      final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
      final net   = qty * price * (1 - disc / 100);
      return s + net + net * (sstMap[r['sst'] ?? 'none'] ?? 0);
    });
  }

  Future<void> _load() async {
    final invoices = await context.read<AppState>().loadInvoices();
    final map = <String, _CustStat>{};
    double totalRev = 0;
    int orders = 0;

    for (final inv in invoices) {
      final cust = (inv['customer'] as Map?) ?? {};
      final name = ((cust['name'] ?? '') as String).trim();
      if (name.isEmpty) continue; // skip invoices without a customer
      final total = _invTotal(inv);
      final date  = (inv['invDate'] ?? '') as String;

      final stat = map.putIfAbsent(name, () => _CustStat(name));
      stat.total += total;
      stat.count += 1;
      totalRev += total;
      orders += 1;
      if (date.isNotEmpty) {
        if (stat.lastDate.isEmpty  || date.compareTo(stat.lastDate)  > 0) stat.lastDate = date;
        if (stat.firstDate.isEmpty || date.compareTo(stat.firstDate) < 0) stat.firstDate = date;
      }
      // Aggregate items the customer buys
      for (final r in (inv['items'] as List? ?? [])) {
        final desc = ((r['desc'] ?? '') as String).trim();
        if (desc.isEmpty) continue;
        final qty   = double.tryParse(r['qty']   ?? '1') ?? 1;
        final price = double.tryParse(r['price'] ?? '0') ?? 0;
        final disc  = double.tryParse(r['disc']  ?? '0') ?? 0;
        final net   = qty * price * (1 - disc / 100);
        stat.itemTotals[desc] = (stat.itemTotals[desc] ?? 0) + net;
        stat.itemQtys[desc]   = (stat.itemQtys[desc] ?? 0) + qty;
      }
    }

    final list = map.values.toList()..sort((a, b) => b.total.compareTo(a.total));
    if (mounted) setState(() {
      _stats = list;
      _totalRevenue = totalRev;
      _orderCount = orders;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final zh   = lang == 'zh';
    final maxTotal = _stats.isNotEmpty ? _stats.first.total : 1.0;
    final avgPerCust = _stats.isNotEmpty ? _totalRevenue / _stats.length : 0.0;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(zh ? '👥 顾客消费分析' : '👥 Customer Analytics'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _stats.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('👥', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(zh ? '暂无客户消费数据' : 'No customer data yet',
                  style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 6),
              Text(zh ? '为发票选择客户后即可生成分析' : 'Assign customers to invoices to see analytics',
                  style: const TextStyle(color: kMuted, fontSize: 12), textAlign: TextAlign.center),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Summary ────────────────────────────────────────────────
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: zh ? '客户数' : 'Customers',
                    value: '${_stats.length}',
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                    label: zh ? '总营业额' : 'Total Revenue',
                    value: fmtMYR(_totalRevenue),
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: zh ? '订单数' : 'Orders',
                    value: '$_orderCount',
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                    label: zh ? '平均每客户' : 'Avg / Customer',
                    value: fmtMYR(avgPerCust),
                  )),
                ]),
                const SizedBox(height: 20),

                // ── Ranking ────────────────────────────────────────────────
                Text(zh ? '客户排行' : 'Top Customers',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
                const SizedBox(height: 10),
                ..._stats.asMap().entries.map((e) => _CustomerRow(
                  rank:  e.key + 1,
                  stat:  e.value,
                  maxTotal: maxTotal,
                  zh:    zh,
                  onTap: () => _showDetail(e.value, zh),
                )),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  void _showDetail(_CustStat s, bool zh) {
    final avg = s.count > 0 ? s.total / s.count : 0.0;
    final topItems = s.itemTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            child: Row(children: [
              Expanded(child: Text(s.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 20, color: kMuted),
              ),
            ]),
          ),
          const Divider(height: 1, color: kBorder),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: zh ? '消费总额' : 'Total Spent', value: fmtMYR(s.total))),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                    label: zh ? '订单数' : 'Orders', value: '${s.count}')),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _MetricCard(
                    label: zh ? '平均客单' : 'Avg Order', value: fmtMYR(avg))),
                  const SizedBox(width: 10),
                  Expanded(child: _MetricCard(
                    label: zh ? '最近购买' : 'Last Order',
                    value: s.lastDate.isNotEmpty ? s.lastDate : '—', small: true)),
                ]),
                if (s.firstDate.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${zh ? '首次购买' : 'First order'}: ${s.firstDate}',
                      style: const TextStyle(fontSize: 12, color: kMuted)),
                ],
                const SizedBox(height: 20),
                Text(zh ? '常买项目' : 'Top Items',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
                const SizedBox(height: 8),
                if (topItems.isEmpty)
                  Text(zh ? '无项目明细' : 'No item details',
                      style: const TextStyle(fontSize: 12, color: kMuted))
                else
                  ...topItems.take(8).map((it) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.key, style: const TextStyle(fontSize: 13, color: kText),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${zh ? '数量' : 'Qty'} ${_fmtQty(s.itemQtys[it.key] ?? 0)}',
                            style: const TextStyle(fontSize: 11, color: kMuted)),
                      ])),
                      Text(fmtMYR(it.value),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
                    ]),
                  )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  static String _fmtQty(double q) =>
      q == q.truncate() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

// ── Data model ──────────────────────────────────────────────────────────────────
class _CustStat {
  final String name;
  double total = 0;
  int    count = 0;
  String lastDate  = '';
  String firstDate = '';
  final Map<String, double> itemTotals = {};
  final Map<String, double> itemQtys   = {};
  _CustStat(this.name);
}

// ── Metric card ───────────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label, value;
  final bool small;
  const _MetricCard({required this.label, required this.value, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface, border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(value, style: TextStyle(
          fontSize: small ? 14 : 19, fontWeight: FontWeight.w900, color: kText)),
    ]),
  );
}

// ── Customer ranking row ────────────────────────────────────────────────────────
class _CustomerRow extends StatelessWidget {
  final int rank;
  final _CustStat stat;
  final double maxTotal;
  final bool zh;
  final VoidCallback onTap;
  const _CustomerRow({required this.rank, required this.stat,
      required this.maxTotal, required this.zh, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = maxTotal > 0 ? (stat.total / maxTotal).clamp(0.0, 1.0) : 0.0;
    final medal = switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '$rank' };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: kSurface, border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Row(children: [
            SizedBox(
              width: 28,
              child: Text(medal, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: rank <= 3 ? 18 : 14,
                      fontWeight: FontWeight.w800, color: kMuted)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(stat.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${stat.count} ${zh ? '单' : 'orders'}'
                   '${stat.lastDate.isNotEmpty ? ' · ${zh ? '最近' : 'last'} ${stat.lastDate}' : ''}',
                  style: const TextStyle(fontSize: 11, color: kMuted)),
            ])),
            const SizedBox(width: 8),
            Text(fmtMYR(stat.total),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kText)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct, minHeight: 5,
              backgroundColor: kBg,
              valueColor: const AlwaysStoppedAnimation(kBlue),
            ),
          ),
        ]),
      ),
    );
  }
}
