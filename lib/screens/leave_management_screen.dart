import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LEAVE MANAGEMENT (Phase 3 Task #14, Pro)
//
// Self-contained: hire dates + leave records live in AppState's leave store
// (SharedPreferences), so the Employee model / DB / cloud sync are untouched.
// Annual entitlement is auto-computed from years of service (Employment Act).
// ═══════════════════════════════════════════════════════════════════════════════

const _leaveTypes = ['annual', 'sick', 'unpaid', 'emergency'];

String _leaveTypeLabel(String t, bool zh) => switch (t) {
  'annual'    => zh ? '年假'   : 'Annual',
  'sick'      => zh ? '病假'   : 'Sick',
  'unpaid'    => zh ? '无薪假' : 'Unpaid',
  'emergency' => zh ? '紧急假' : 'Emergency',
  _           => t,
};

Color _leaveTypeColor(String t) => switch (t) {
  'annual'    => kBlue,
  'sick'      => const Color(0xFFF59E0B),
  'unpaid'    => kMuted,
  'emergency' => kRed,
  _           => kMuted,
};

int yearsOfService(String hireDate) {
  final d = DateTime.tryParse(hireDate);
  if (d == null) return 0;
  final now = DateTime.now();
  var y = now.year - d.year;
  if (now.month < d.month || (now.month == d.month && now.day < d.day)) y--;
  return y < 0 ? 0 : y;
}

class LeaveManagementScreen extends StatefulWidget {
  const LeaveManagementScreen({super.key});
  @override State<LeaveManagementScreen> createState() => _LeaveState();
}

class _LeaveState extends State<LeaveManagementScreen> {
  Map<String, dynamic> _store = {'hireDates': {}, 'records': []};
  Employee? _emp;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final s = await context.read<AppState>().loadLeaveStore();
    if (mounted) setState(() { _store = s; _loading = false; });
  }

  Future<void> _persist() async {
    await context.read<AppState>().saveLeaveStore(_store);
    if (mounted) setState(() {});
  }

  Map<String, dynamic> get _hireDates => Map<String, dynamic>.from(_store['hireDates'] ?? {});
  List<Map<String, dynamic>> get _records =>
      ((_store['records'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

  String? _hireDate(String empId) => _hireDates[empId] as String?;

  List<Map<String, dynamic>> _empRecords(String empId) {
    final yr = DateTime.now().year;
    return _records.where((r) =>
      '${r['empId']}' == empId && (r['from'] as String? ?? '').startsWith('$yr')).toList()
      ..sort((a, b) => (b['from'] ?? '').compareTo(a['from'] ?? ''));
  }

  double _usedAnnual(String empId) => _empRecords(empId)
      .where((r) => r['type'] == 'annual')
      .fold<double>(0, (s, r) => s + ((r['days'] as num?)?.toDouble() ?? 0));

  Future<void> _setHireDate(String empId) async {
    final init = DateTime.tryParse(_hireDate(empId) ?? '') ?? DateTime.now();
    final picked = await showDatePicker(
      context: context, initialDate: init,
      firstDate: DateTime(2000), lastDate: DateTime.now(),
    );
    if (picked == null) return;
    _hireDates[empId] = picked.toIso8601String().substring(0, 10);
    _store['hireDates'] = _hireDates;
    await _persist();
  }

  Future<void> _addLeave(String empId, String empName) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _AddLeaveSheet(empName: empName),
    );
    if (result == null) return;
    final list = _records;
    list.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'empId': empId, 'empName': empName,
      ...result,
    });
    _store['records'] = list;
    await _persist();
  }

  Future<void> _deleteLeave(int id) async {
    final list = _records..removeWhere((r) => r['id'] == id);
    _store['records'] = list;
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final lang = app.settings.lang;
    final zh   = lang == 'zh';
    final emps = app.employees;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(zh ? '🏖️ 请假管理' : '🏖️ Leave Management'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : emps.isEmpty
          ? Center(child: Text(zh ? '请先添加员工' : 'Add employees first',
              style: const TextStyle(color: kMuted, fontSize: 14)))
          : Column(children: [
              // Employee selector
              Container(
                color: kSurface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: DropdownButtonFormField<int>(
                  value: _emp?.id,
                  hint: Text(zh ? '选择员工' : 'Select employee', style: const TextStyle(fontSize: 13)),
                  items: emps.map((e) => DropdownMenuItem(value: e.id,
                    child: Text(e.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
                  onChanged: (v) => setState(() => _emp = emps.firstWhere((e) => e.id == v)),
                  decoration: InputDecoration(
                    filled: true, fillColor: kBg, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                  ),
                ),
              ),
              Expanded(child: _emp == null
                ? Center(child: Text(zh ? '请选择员工' : 'Select an employee',
                    style: const TextStyle(color: kMuted, fontSize: 14)))
                : _empView(_emp!, zh)),
            ]),
      floatingActionButton: _emp == null ? null : FloatingActionButton.extended(
        onPressed: () => _addLeave('${_emp!.id}', _emp!.name),
        backgroundColor: kDark, foregroundColor: Colors.white,
        icon: const Icon(Icons.add), label: Text(zh ? '请假' : 'Add Leave'),
      ),
    );
  }

  Widget _empView(Employee emp, bool zh) {
    final empId = '${emp.id}';
    final hire  = _hireDate(empId);
    final yos   = hire != null ? yearsOfService(hire) : 0;
    final entitlement = hire != null ? statutoryAnnualLeave(yos) : 0;
    final used  = _usedAnnual(empId);
    final remaining = entitlement - used;
    final recs  = _empRecords(empId);

    return ListView(padding: const EdgeInsets.all(16), children: [
      // Hire date / service
      GestureDetector(
        onTap: () => _setHireDate(empId),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.event, size: 18, color: kBlue),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(zh ? '入职日期' : 'Hire Date', style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
              Text(hire ?? (zh ? '点击设置（用于年假额度）' : 'Tap to set (for leave entitlement)'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: hire != null ? kText : kMuted)),
            ])),
            if (hire != null)
              Text(zh ? '工龄 $yos 年' : '$yos yr${yos == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w600)),
            const Icon(Icons.chevron_right, color: kMuted),
          ]),
        ),
      ),
      const SizedBox(height: 12),

      if (hire == null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kBlueBg, border: Border.all(color: kBlueBd), borderRadius: BorderRadius.circular(12)),
          child: Text(zh
            ? '设置入职日期后，将按马来西亚法定年资自动计算年假额度（<2年 8天，2–5年 12天，>5年 16天）。'
            : 'Set the hire date to auto-compute statutory annual leave (<2y 8d, 2–5y 12d, >5y 16d).',
            style: const TextStyle(fontSize: 12, color: kBlue)),
        )
      else
        // Annual leave balance
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(zh ? '年假余额' : 'Annual Leave Balance', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              Text(zh ? '$remaining / $entitlement 天' : '$remaining / $entitlement days',
                style: TextStyle(color: remaining > 0 ? const Color(0xFF4ADE80) : const Color(0xFFF87171), fontWeight: FontWeight.w900, fontSize: 18)),
            ]),
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(
              value: entitlement > 0 ? (used / entitlement).clamp(0.0, 1.0) : 0,
              minHeight: 6, backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4ADE80)),
            )),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text(
              zh ? '已用 ${used.toStringAsFixed(used == used.truncate() ? 0 : 1)} 天 · ${DateTime.now().year} 年'
                 : 'Used ${used.toStringAsFixed(used == used.truncate() ? 0 : 1)} days · ${DateTime.now().year}',
              style: const TextStyle(color: Colors.white70, fontSize: 11))),
          ]),
        ),
      const SizedBox(height: 16),

      Text(zh ? '请假记录（本年）' : 'Leave Records (this year)',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
      const SizedBox(height: 8),
      if (recs.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text(zh ? '暂无请假记录' : 'No leave records yet',
            style: const TextStyle(color: kMuted, fontSize: 13))))
      else
        ...recs.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _leaveTypeColor(r['type']).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _leaveTypeColor(r['type']).withOpacity(0.3)),
              ),
              child: Text(_leaveTypeLabel(r['type'], zh),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _leaveTypeColor(r['type']))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['from']} → ${r['to']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
              if ((r['reason'] ?? '').toString().isNotEmpty)
                Text(r['reason'], style: const TextStyle(fontSize: 11, color: kMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            Text('${(r['days'] as num?)?.toString() ?? '0'} ${zh ? '天' : 'd'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(width: 6),
            GestureDetector(onTap: () => _deleteLeave(r['id']),
              child: const Icon(Icons.close, size: 16, color: kMuted)),
          ]),
        )),
      const SizedBox(height: 80),
    ]);
  }
}

// ── Add leave sheet ────────────────────────────────────────────────────────────
class _AddLeaveSheet extends StatefulWidget {
  final String empName;
  const _AddLeaveSheet({required this.empName});
  @override State<_AddLeaveSheet> createState() => _AddLeaveSheetState();
}

class _AddLeaveSheetState extends State<_AddLeaveSheet> {
  String _type = 'annual';
  DateTime _from = DateTime.now();
  DateTime _to   = DateTime.now();
  String _reason = '';

  double get _days => _to.difference(_from).inDays + 1.0;

  String _fmt(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _pick(bool isFrom) async {
    final picked = await showDatePicker(
      context: context, initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) { _from = picked; if (_to.isBefore(_from)) _to = _from; }
      else { _to = picked.isBefore(_from) ? _from : picked; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final zh = context.read<AppState>().settings.lang == 'zh';
    return Container(
      decoration: const BoxDecoration(color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(zh ? '添加请假 · ${widget.empName}' : 'Add Leave · ${widget.empName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: kMuted)),
          ]),
          const SizedBox(height: 16),
          Text(zh ? '类型' : 'Type', style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: _leaveTypes.map((t) {
            final sel = _type == t;
            return GestureDetector(
              onTap: () => setState(() => _type = t),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? _leaveTypeColor(t).withOpacity(0.12) : kBg,
                  border: Border.all(color: sel ? _leaveTypeColor(t) : kBorder, width: sel ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_leaveTypeLabel(t, zh),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: sel ? _leaveTypeColor(t) : kMuted)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _dateField(zh ? '从' : 'From', _fmt(_from), () => _pick(true))),
            const SizedBox(width: 10),
            Expanded(child: _dateField(zh ? '至' : 'To', _fmt(_to), () => _pick(false))),
          ]),
          const SizedBox(height: 6),
          Text(zh ? '共 ${_days.toStringAsFixed(0)} 天' : '${_days.toStringAsFixed(0)} day(s)',
            style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => _reason = v,
            decoration: InputDecoration(
              labelText: zh ? '原因（可选）' : 'Reason (optional)',
              labelStyle: const TextStyle(fontSize: 12, color: kMuted),
              filled: true, fillColor: kBg, isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(context, {
              'type': _type, 'from': _fmt(_from), 'to': _fmt(_to),
              'days': _days, 'reason': _reason,
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(zh ? '保存请假' : 'Save Leave', style: const TextStyle(fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, color: kText, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
