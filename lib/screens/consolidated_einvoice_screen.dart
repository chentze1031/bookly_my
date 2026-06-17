import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../utils.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import '../services/myinvois_service.dart';
import '../widgets/common.dart';
import 'sub_screen.dart' show showSubSheet;

// ════════════════════════════════════════════════════════════════════════════
// Consolidated e-Invoice (Phase 4 #28 v2, D1)
//
// LHDN lets B2C transactions that weren't individually e-invoiced be aggregated
// into ONE monthly "consolidated e-Invoice" (buyer = general public). This sheet
// picks a month, lists eligible B2C invoices (no buyer TIN, not yet validated),
// and submits them as a single consolidated document.
// ════════════════════════════════════════════════════════════════════════════

const _sstRate = {'none': 0.0, 'sst5': 0.05, 'sst10': 0.10};

double invoiceGrand(Map<String, dynamic> inv) {
  final items = (inv['items'] as List?) ?? [];
  double t = 0;
  for (final it in items) {
    final qty = double.tryParse('${it['qty'] ?? '1'}') ?? 1;
    final price = double.tryParse('${it['price'] ?? '0'}') ?? 0;
    t += qty * price * (1 + (_sstRate[it['sst'] ?? 'none'] ?? 0));
  }
  return t;
}

Future<void> showConsolidatedSheet(BuildContext context) =>
    showAppSheet(context: context, fullHeight: true, child: const ConsolidatedSheet());

class ConsolidatedSheet extends StatefulWidget {
  const ConsolidatedSheet({super.key});
  @override
  State<ConsolidatedSheet> createState() => _ConsolidatedSheetState();
}

class _ConsolidatedSheetState extends State<ConsolidatedSheet> {
  List<Map<String, dynamic>> _all = [];
  String _month = '';
  final Set<String> _selected = {};
  bool _loading = true;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final list = await app.loadInvoices();
    // Eligible = B2C (no buyer TIN) and not already validated/in-progress/done.
    bool eligible(Map<String, dynamic> inv) {
      final cust = (inv['customer'] as Map?) ?? {};
      final tin = (cust['tin'] ?? '').toString().trim();
      final st = (inv['miStatus'] ?? 'none').toString();
      return tin.isEmpty &&
          !{'Valid', 'InProgress', 'Cancelled', 'Consolidated'}.contains(st);
    }

    _all = list.where(eligible).toList();
    final months = _all
        .map((e) => (e['invDate'] ?? '').toString())
        .where((d) => d.length >= 7)
        .map((d) => d.substring(0, 7))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    _month = months.isNotEmpty ? months.first : '';
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _candidates =>
      _all.where((e) => (e['invDate'] ?? '').toString().startsWith(_month)).toList();

  List<String> get _months {
    final s = _all
        .map((e) => (e['invDate'] ?? '').toString())
        .where((d) => d.length >= 7)
        .map((d) => d.substring(0, 7))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return s;
  }

  double get _selectedTotal => _candidates
      .where((e) => _selected.contains(e['invNo']))
      .fold(0.0, (a, e) => a + invoiceGrand(e));

  Future<void> _submit(String lang) async {
    final sub = context.read<SubState>();
    if (!sub.isPro) { showSubSheet(context); return; }
    final app = context.read<AppState>();
    final picked = _candidates.where((e) => _selected.contains(e['invNo'])).toList();
    if (picked.isEmpty) return;
    setState(() { _busy = true; _result = null; });
    final consNo = 'CONS-${_month.replaceAll('-', '')}';
    final r = await MyInvoisService.submitConsolidated(
      invoices: picked, supplier: app.settings, consolidatedInvNo: consNo);
    // On accept, tag the source invoices so they don't reappear as candidates.
    if (r.ok) {
      for (final inv in picked) {
        await app.updateInvoiceMyInvois((inv['invNo'] ?? '').toString(),
            {'miStatus': 'Consolidated', 'miConsolidatedNo': consNo});
      }
    }
    if (mounted) setState(() {
      _busy = false;
      _ok = r.ok;
      _result = r.ok
          ? tr(lang, 'Submitted as $consNo (status: In progress).',
                  '已作为 $consNo 提交（状态：处理中）。',
                  'Dihantar sebagai $consNo (status: Diproses).')
          : (r.error ?? tr(lang, 'Submit failed', '提交失败', 'Gagal hantar'));
      if (r.ok) { _selected.clear(); _load(); }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final loggedIn = MyInvoisService.isLoggedIn;
    final cands = _candidates;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          Expanded(child: Text(
            tr(lang, 'Consolidated e-Invoice', '合并发票', 'e-Invois Disatukan'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText))),
          IconButton(icon: Icon(Icons.close, color: kMuted), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : !loggedIn
            ? Padding(padding: const EdgeInsets.all(20),
                child: Text(tr(lang,
                  'Sign in + configure MyInvois in Settings first.',
                  '请先登录并在设置里配置 MyInvois。',
                  'Log masuk + konfigur MyInvois dahulu.'),
                  style: const TextStyle(color: kMuted)))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(lang,
                    'Aggregate B2C invoices (no buyer TIN, not yet submitted) into one e-Invoice for the month.',
                    '将本月未单独提交的 B2C 发票（无买方 TIN）合并为一张电子发票。',
                    'Gabungkan invois B2C (tiada TIN pembeli, belum dihantar) jadi satu e-Invois bulanan.'),
                    style: const TextStyle(fontSize: 12, color: kMuted)),
                  const SizedBox(height: 12),

                  if (_months.isEmpty)
                    Text(tr(lang, 'No eligible B2C invoices found.', '没有可合并的 B2C 发票。', 'Tiada invois B2C layak.'),
                        style: const TextStyle(color: kMuted))
                  else ...[
                    // Month selector
                    Row(children: [
                      Text(tr(lang, 'Month', '月份', 'Bulan'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _month, dropdownColor: kSurface,
                            style: TextStyle(fontSize: 14, color: kText),
                            items: [for (final m in _months) DropdownMenuItem(value: m, child: Text(m))],
                            onChanged: (v) => setState(() { _month = v ?? _month; _selected.clear(); }),
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          if (_selected.length == cands.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(cands.map((e) => (e['invNo'] ?? '').toString()));
                          }
                        }),
                        child: Text(_selected.length == cands.length
                            ? tr(lang, 'Clear', '清空', 'Kosong')
                            : tr(lang, 'Select all', '全选', 'Pilih semua')),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    for (final inv in cands) _row(lang, inv),
                  ],

                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _ok ? kGreenBg : kRedBg,
                        border: Border.all(color: (_ok ? kGreen : kRed).withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(_result!, style: TextStyle(fontSize: 12, color: _ok ? kGreen : kRed)),
                    ),
                  ],
                ]),
              ),
      ),
      if (!_loading && loggedIn && _months.isNotEmpty)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(child: Text(
                '${_selected.length} ${tr(lang, 'selected', '已选', 'dipilih')} · RM ${_selectedTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText))),
              ElevatedButton(
                onPressed: (_busy || _selected.isEmpty) ? null : () => _submit(lang),
                style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
                child: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(tr(lang, 'Submit consolidated', '提交合并发票', 'Hantar disatukan')),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _row(String lang, Map<String, dynamic> inv) {
    final no = (inv['invNo'] ?? '').toString();
    final sel = _selected.contains(no);
    return GestureDetector(
      onTap: () => setState(() => sel ? _selected.remove(no) : _selected.add(no)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? kGreen.withValues(alpha: 0.06) : kBg,
          border: Border.all(color: sel ? kGreen.withValues(alpha: 0.4) : kBorder),
          borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(sel ? Icons.check_box : Icons.check_box_outline_blank,
              size: 20, color: sel ? kGreen : kMuted),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(no, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
            Text((inv['invDate'] ?? '').toString(), style: const TextStyle(fontSize: 11, color: kMuted)),
          ])),
          Text('RM ${invoiceGrand(inv).toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
        ]),
      ),
    );
  }
}
