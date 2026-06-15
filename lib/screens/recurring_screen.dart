import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../utils.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RECURRING TRANSACTIONS (Phase 4 #21, Pro)
// Templates auto-generate transactions on launch (catch-up, de-duplicated).
// ═══════════════════════════════════════════════════════════════════════════════

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override State<RecurringScreen> createState() => _RecurringState();
}

class _RecurringState extends State<RecurringScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    // Generate any due ones first, then show the (updated) templates.
    await context.read<AppState>().processRecurring();
    final l = await context.read<AppState>().loadRecurring();
    if (mounted) setState(() { _list = l; _loading = false; });
  }

  Future<void> _edit([Map<String, dynamic>? tpl]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _RecurringSheet(existing: tpl),
    );
    if (result == null) return;
    await context.read<AppState>().saveRecurring(result);
    _load();
  }

  Future<void> _toggle(Map<String, dynamic> tpl) async {
    tpl = Map<String, dynamic>.from(tpl)..['active'] = !(tpl['active'] != false);
    await context.read<AppState>().saveRecurring(tpl);
    _load();
  }

  Future<void> _delete(int id) async {
    await context.read<AppState>().deleteRecurring(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final zh  = app.settings.lang == 'zh';
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(zh ? '🔁 定期记账' : '🔁 Recurring'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.add, color: kText), onPressed: () => _edit())],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔁', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(zh ? '还没有定期记账' : 'No recurring entries yet', style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 6),
              Text(zh ? '如：每月租金、订阅费' : 'e.g. monthly rent, subscriptions', style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add),
                label: Text(zh ? '新增' : 'Add'),
                style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
            ]))
          : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              ..._list.map((tpl) {
              final cat = findCat(tpl['catId'] as String? ?? '');
              final active = tpl['active'] != false;
              final isIncome = tpl['type'] == 'income';
              final amount = (tpl['amount'] as num?)?.toDouble() ?? 0;
              final freq = tpl['freq'] == 'weekly' ? (zh ? '每周' : 'Weekly') : (zh ? '每月' : 'Monthly');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Text(cat?.icon ?? '🔁', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((zh ? tpl['descZH'] : tpl['descEN']) ?? cat?.label(app.settings.lang) ?? '',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: active ? kText : kMuted)),
                    Text('$freq · ${zh ? '下次' : 'next'} ${tpl['nextDate'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, color: kMuted)),
                  ])),
                  Text('${isIncome ? '+' : '-'}${fmtMYR(amount)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: isIncome ? kGreen : kRed)),
                  const SizedBox(width: 6),
                  Switch(value: active, onChanged: (_) => _toggle(tpl), activeColor: kDark),
                  GestureDetector(onTap: () => _delete(tpl['id'] as int),
                    child: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.delete_outline, size: 20, color: kRed))),
                ]),
              );
            }),
            Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(zh ? '到期的交易会在打开 App 时自动生成（标记"自动"）。' : 'Due transactions are generated automatically on app launch (marked "auto").',
                style: const TextStyle(fontSize: 11, color: kMuted))),
          ]),
      floatingActionButton: _list.isEmpty ? null : FloatingActionButton(
        onPressed: () => _edit(), backgroundColor: kDark, foregroundColor: Colors.white, child: const Icon(Icons.add)),
    );
  }
}

// ── Add/edit sheet ─────────────────────────────────────────────────────────────
class _RecurringSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _RecurringSheet({this.existing});
  @override State<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<_RecurringSheet> {
  String _type = 'expense';
  String? _catId;
  double _amount = 0;
  String _desc = '';
  String _freq = 'monthly';
  DateTime _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type  = e['type'] ?? 'expense';
      _catId = e['catId'];
      _amount = (e['amount'] as num?)?.toDouble() ?? 0;
      _freq  = e['freq'] ?? 'monthly';
      _start = DateTime.tryParse(e['nextDate'] ?? '') ?? DateTime.now();
      final zh = false; // desc captured generically below
      _desc  = (zh ? e['descZH'] : e['descEN']) ?? e['descEN'] ?? '';
    }
  }

  List get _cats => _type == 'income' ? incomeCategories : expenseCategories;

  @override
  Widget build(BuildContext context) {
    final zh = context.read<AppState>().settings.lang == 'zh';
    if (_catId != null && !_cats.any((c) => c.id == _catId)) _catId = null;

    return Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(zh ? '定期记账' : 'Recurring Entry', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: kMuted)),
          ]),
          const SizedBox(height: 14),
          // Type toggle
          Row(children: [
            for (final ty in [('expense', zh ? '支出' : 'Expense'), ('income', zh ? '收入' : 'Income')])
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _type = ty.$1; _catId = null; }),
                child: Container(
                  margin: EdgeInsets.only(right: ty.$1 == 'expense' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _type == ty.$1 ? (ty.$1 == 'income' ? kGreen : kRed) : kBg,
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                  child: Text(ty.$2, textAlign: TextAlign.center, style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: _type == ty.$1 ? Colors.white : kMuted)),
                ),
              )),
          ]),
          const SizedBox(height: 12),
          // Category
          DropdownButtonFormField<String>(
            value: _catId,
            isExpanded: true,
            hint: Text(zh ? '选择分类' : 'Select category', style: const TextStyle(fontSize: 13)),
            items: _cats.map<DropdownMenuItem<String>>((c) => DropdownMenuItem(value: c.id as String,
              child: Text('${c.icon}  ${c.label(zh ? 'zh' : 'en')}', style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setState(() => _catId = v),
            decoration: _dec(),
          ),
          const SizedBox(height: 12),
          // Amount + desc
          TextFormField(
            initialValue: _amount > 0 ? _amount.toStringAsFixed(_amount == _amount.truncate() ? 0 : 2) : '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => _amount = double.tryParse(v) ?? 0,
            decoration: _dec(label: zh ? '金额 (RM)' : 'Amount (RM)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _desc,
            onChanged: (v) => _desc = v,
            decoration: _dec(label: zh ? '备注（可选）' : 'Note (optional)'),
          ),
          const SizedBox(height: 12),
          // Frequency
          Row(children: [
            for (final fr in [('monthly', zh ? '每月' : 'Monthly'), ('weekly', zh ? '每周' : 'Weekly')])
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _freq = fr.$1),
                child: Container(
                  margin: EdgeInsets.only(right: fr.$1 == 'monthly' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: _freq == fr.$1 ? kDark : kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                  child: Text(fr.$2, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _freq == fr.$1 ? Colors.white : kMuted)),
                ),
              )),
          ]),
          const SizedBox(height: 12),
          // Start date
          GestureDetector(
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (p != null) setState(() => _start = p);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.event, size: 18, color: kBlue), const SizedBox(width: 10),
                Text('${zh ? '开始/下次日期' : 'Start / next date'}: ${_start.toIso8601String().substring(0, 10)}',
                  style: const TextStyle(fontSize: 14, color: kText, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: (_catId == null || _amount <= 0) ? null : () {
              final cat = findCat(_catId!);
              Navigator.pop(context, {
                'id': widget.existing?['id'] ?? DateTime.now().millisecondsSinceEpoch,
                'type': _type, 'catId': _catId, 'amount': _amount,
                'descEN': _desc.isNotEmpty ? _desc : (cat?.enLabel ?? ''),
                'descZH': _desc.isNotEmpty ? _desc : (cat?.zhLabel ?? ''),
                'freq': _freq, 'anchorDay': _start.day,
                'nextDate': _start.toIso8601String().substring(0, 10),
                'active': widget.existing?['active'] ?? true,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text(zh ? '保存' : 'Save', style: const TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  InputDecoration _dec({String? label}) => InputDecoration(
    labelText: label, labelStyle: const TextStyle(fontSize: 12, color: kMuted),
    filled: true, fillColor: kBg, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
  );
}
