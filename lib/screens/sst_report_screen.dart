import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../state/app_state.dart';
import '../models.dart';

// ════════════════════════════════════════════════════════════════════════════
// SST-02 申报摘要报表（第一阶段 Task 2）
//
// 按双月区间显示 SST 汇总：
//  - 每个税率的应税销售额、应收 SST
//  - 区分销售税（Sales Tax）和服务税（Service Tax）
//  - 用于辅助 Customs SST-02 申报，不等于官方表格
// ════════════════════════════════════════════════════════════════════════════

class SstReportScreen extends StatefulWidget {
  const SstReportScreen({super.key});

  @override
  State<SstReportScreen> createState() => _SstReportScreenState();
}

class _SstReportScreenState extends State<SstReportScreen> {
  // Bi-monthly periods: Jan-Feb, Mar-Apr, May-Jun, Jul-Aug, Sep-Oct, Nov-Dec
  late String _period; // format: "YYYY-MM/YYYY-MM"

  @override
  void initState() {
    super.initState();
    _period = _currentPeriod();
  }

  static String _currentPeriod() {
    final now = DateTime.now();
    final startMonth = now.month % 2 == 0 ? now.month - 1 : now.month;
    final endMonth   = startMonth + 1;
    final y = now.year;
    return '${y.toString()}-${startMonth.toString().padLeft(2,'0')}/'
           '${y.toString()}-${endMonth.toString().padLeft(2,'0')}';
  }

  List<String> _buildPeriods(List<Transaction> txs) {
    final months = txs.map((t) => t.date.substring(0, 7)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final periods = <String>{};
    for (final m in months) {
      final parts = m.split('-');
      final y = parts[0]; final mo = int.parse(parts[1]);
      final startMo = mo % 2 == 0 ? mo - 1 : mo;
      final endMo   = startMo + 1;
      periods.add('$y-${startMo.toString().padLeft(2,'0')}/$y-${endMo.toString().padLeft(2,'0')}');
    }
    // always include current period
    periods.add(_currentPeriod());
    return periods.toList()..sort((a, b) => b.compareTo(a));
  }

  List<Transaction> _filterByPeriod(List<Transaction> txs) {
    final parts   = _period.split('/');
    final fromStr = '${parts[0]}-01';
    final toMonth = parts[1];
    final toParts = toMonth.split('-');
    final lastDay = DateTime(int.parse(toParts[0]), int.parse(toParts[1]) + 1, 0).day;
    final toStr   = '$toMonth-$lastDay';
    return txs.where((t) => t.date.compareTo(fromStr) >= 0 && t.date.compareTo(toStr) <= 0).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;
    final txs  = app.txs.where((t) => t.sstKey != 'none' && t.sstMYR > 0).toList();

    final periods  = _buildPeriods(txs);
    final filtered = _filterByPeriod(txs);

    // Group by sstKey
    final Map<String, _SstGroup> groups = {};
    for (final tx in filtered) {
      if (tx.sstKey == 'none' || tx.sstMYR <= 0) continue;
      groups.putIfAbsent(tx.sstKey, () => _SstGroup(tx.sstKey));
      groups[tx.sstKey]!.add(tx);
    }

    final salesGroups   = groups.values.where((g) => g.key.startsWith('sst')).toList();
    final serviceGroups = groups.values.where((g) => g.key.startsWith('service')).toList();

    final totalSalesTaxable = salesGroups.fold<double>(0, (s, g) => s + g.taxable);
    final totalSalesSST     = salesGroups.fold<double>(0, (s, g) => s + g.sstTotal);
    final totalServiceTaxable = serviceGroups.fold<double>(0, (s, g) => s + g.taxable);
    final totalServiceSST   = serviceGroups.fold<double>(0, (s, g) => s + g.sstTotal);

    final periodLabel = _period.replaceFirst('/', ' → ');

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          lang == 'zh' ? '🧾 SST-02 申报摘要' : '🧾 SST-02 Summary',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText),
        ),
      ),
      body: Column(
        children: [
          // ── Period selector ──────────────────────────────────────────────
          Container(
            color: kSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                lang == 'zh' ? '申报期间（双月）' : 'Bi-Monthly Period',
                style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: periods.contains(_period) ? _period : periods.first,
                items: periods.map((p) => DropdownMenuItem(
                  value: p,
                  child: Text(p.replaceFirst('/', ' → '),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                )).toList(),
                onChanged: (v) { if (v != null) setState(() => _period = v); },
                decoration: InputDecoration(
                  filled: true, fillColor: kBg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ]),
          ),

          Expanded(
            child: filtered.isEmpty
              ? _EmptyState(lang: lang)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── Info banner ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kBlueBg, border: Border.all(color: kBlueBd),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('ℹ️', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          lang == 'zh'
                            ? '此摘要基于已记录交易中的 SST 数据生成，仅供申报参考。请在 MySST 系统上进行正式申报。'
                            : 'This summary is based on SST data from recorded transactions. For reference only — file officially on the MySST portal.',
                          style: const TextStyle(fontSize: 11, color: kBlue),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // ── Sales Tax section ───────────────────────────────────
                    if (salesGroups.isNotEmpty) ...[
                      _sectionHeader(lang == 'zh' ? '销售税（Sales Tax）' : 'Sales Tax'),
                      const SizedBox(height: 8),
                      _SstTable(groups: salesGroups, lang: lang,
                        totalTaxable: totalSalesTaxable, totalSST: totalSalesSST),
                      const SizedBox(height: 16),
                    ],

                    // ── Service Tax section ─────────────────────────────────
                    if (serviceGroups.isNotEmpty) ...[
                      _sectionHeader(lang == 'zh' ? '服务税（Service Tax）' : 'Service Tax'),
                      const SizedBox(height: 8),
                      _SstTable(groups: serviceGroups, lang: lang,
                        totalTaxable: totalServiceTaxable, totalSST: totalServiceSST),
                      const SizedBox(height: 16),
                    ],

                    // ── Grand total ─────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kDark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            lang == 'zh' ? '本期应缴 SST 总额' : 'Total SST Payable',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          Text(
                            'RM ${fmtAmt(totalSalesSST + totalServiceSST)}',
                            style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.w900,
                              fontSize: 18, fontFamily: 'Georgia'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      lang == 'zh'
                        ? '期间: $periodLabel'
                        : 'Period: $periodLabel',
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                    const SizedBox(height: 30),
                  ]),
                ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Text(
    label,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kMuted, letterSpacing: 0.5),
  );
}

// ── Data model ────────────────────────────────────────────────────────────────
class _SstGroup {
  final String key;
  double taxable  = 0;
  double sstTotal = 0;
  int    count    = 0;
  _SstGroup(this.key);

  void add(Transaction tx) {
    taxable  += tx.amountMYR;
    sstTotal += tx.sstMYR;
    count++;
  }

  String label(String lang) => sstRates[key]?.let((r) => lang == 'zh' ? r.zhLabel : r.enLabel) ?? key;
  double get rate => sstRates[key]?.rate ?? 0;
}

// ── SST table widget ──────────────────────────────────────────────────────────
class _SstTable extends StatelessWidget {
  final List<_SstGroup> groups;
  final String lang;
  final double totalTaxable, totalSST;
  const _SstTable({required this.groups, required this.lang,
    required this.totalTaxable, required this.totalSST});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
          ),
          child: Row(children: [
            Expanded(flex: 3, child: Text(lang == 'zh' ? '税率' : 'Rate',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted))),
            Expanded(flex: 3, child: Text(lang == 'zh' ? '应税额 (RM)' : 'Taxable (RM)',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted))),
            Expanded(flex: 3, child: Text(lang == 'zh' ? 'SST (RM)' : 'SST (RM)',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted))),
          ]),
        ),
        // Rows
        ...groups.map((g) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kBorder))),
          child: Row(children: [
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.label(lang), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
              Text('${g.count} tx', style: const TextStyle(fontSize: 10, color: kMuted)),
            ])),
            Expanded(flex: 3, child: Text(fmtAmt(g.taxable),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: kText))),
            Expanded(flex: 3, child: Text(fmtAmt(g.sstTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText))),
          ]),
        )),
        // Subtotal
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            color: kBg,
            border: Border(top: BorderSide(color: kBorder, width: 1.5)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
          ),
          child: Row(children: [
            Expanded(flex: 3, child: Text(lang == 'zh' ? '小计' : 'Subtotal',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kText))),
            Expanded(flex: 3, child: Text(fmtAmt(totalTaxable),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText))),
            Expanded(flex: 3, child: Text(fmtAmt(totalSST),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kRed))),
          ]),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String lang;
  const _EmptyState({required this.lang});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🧾', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text(
          lang == 'zh' ? '本期无 SST 交易记录' : 'No SST transactions this period',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          lang == 'zh'
            ? '请先在记账中为收入/支出添加 SST 税率'
            : 'Add SST rates to your income/expense transactions first',
          style: const TextStyle(fontSize: 12, color: kMuted),
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ── Number format helper ──────────────────────────────────────────────────────
String fmtAmt(double v) {
  if (v == 0) return '0.00';
  return v.toStringAsFixed(2).replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
}
