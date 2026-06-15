import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../services/inventory_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// WAREHOUSES / STORES (Phase 4 #25, Pro)
//
// Self-contained: warehouse list + item→warehouse assignment live in AppState's
// warehouse store (SharedPreferences). The synced inventory model is untouched.
// Each item belongs to at most one warehouse.
// ═══════════════════════════════════════════════════════════════════════════════

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key});
  @override State<WarehouseScreen> createState() => _WarehouseState();
}

class _WarehouseState extends State<WarehouseScreen> {
  Map<String, dynamic> _store = {'list': [], 'assign': {}};
  int? _managing; // warehouse id whose items are being assigned
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final s = await context.read<AppState>().loadWarehouseStore();
    if (mounted) setState(() { _store = s; _loading = false; });
  }
  Future<void> _persist() async {
    await context.read<AppState>().saveWarehouseStore(_store);
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _list =>
      ((_store['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic> get _assign => Map<String, dynamic>.from(_store['assign'] ?? {});

  Future<void> _addOrRename({Map<String, dynamic>? wh}) async {
    final ctrl = TextEditingController(text: wh?['name'] ?? '');
    final zh = context.read<AppState>().settings.lang == 'zh';
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: Text(wh == null ? (zh ? '新增仓库/门店' : 'New Warehouse') : (zh ? '重命名' : 'Rename')),
      content: TextField(controller: ctrl, autofocus: true,
        decoration: InputDecoration(hintText: zh ? '名称' : 'Name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(zh ? '取消' : 'Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(zh ? '保存' : 'Save')),
      ],
    ));
    if (name == null || name.isEmpty) return;
    final list = _list;
    if (wh == null) {
      list.add({'id': DateTime.now().millisecondsSinceEpoch, 'name': name});
    } else {
      final idx = list.indexWhere((w) => w['id'] == wh['id']);
      if (idx >= 0) list[idx] = {...list[idx], 'name': name};
    }
    _store['list'] = list;
    await _persist();
  }

  Future<void> _delete(int id) async {
    _store['list'] = _list..removeWhere((w) => w['id'] == id);
    // Unassign items from the deleted warehouse
    final a = _assign..removeWhere((k, v) => v == id);
    _store['assign'] = a;
    await _persist();
  }

  Future<void> _toggleAssign(int itemId, int whId) async {
    final a = _assign;
    if (a['$itemId'] == whId) { a.remove('$itemId'); } else { a['$itemId'] = whId; }
    _store['assign'] = a;
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final zh  = context.watch<AppState>().settings.lang == 'zh';
    final inv = context.watch<InventoryState>();

    if (_managing != null) {
      final wh = _list.firstWhere((w) => w['id'] == _managing, orElse: () => {'id': _managing, 'name': ''});
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _managing = null)),
          title: Text('${zh ? '分配物品' : 'Assign'} · ${wh['name']}'),
        ),
        body: inv.items.isEmpty
          ? Center(child: Text(zh ? '暂无库存物品' : 'No inventory items', style: const TextStyle(color: kMuted)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(zh ? '勾选属于本仓库的物品（一个物品只能在一个仓库）' : 'Tick items in this warehouse (one warehouse per item)',
                style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 8),
              ...inv.items.map((it) {
                final assignedHere = _assign['${it.id}'] == _managing;
                final elsewhereId = _assign['${it.id}'];
                final elsewhere = elsewhereId != null && elsewhereId != _managing
                    ? _list.firstWhere((w) => w['id'] == elsewhereId, orElse: () => {'name': '?'})['name']
                    : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: kSurface, border: Border.all(color: assignedHere ? kGreenBd : kBorder), borderRadius: BorderRadius.circular(12)),
                  child: CheckboxListTile(
                    value: assignedHere,
                    activeColor: kGreen,
                    onChanged: (_) => _toggleAssign(it.id, _managing!),
                    title: Text(it.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
                    subtitle: Text([
                      if (it.sku.isNotEmpty) it.sku,
                      '${zh ? '库存' : 'Qty'} ${it.qty % 1 == 0 ? it.qty.toInt() : it.qty}',
                      if (elsewhere != null) '${zh ? '现属' : 'in'}: $elsewhere',
                    ].join(' · '), style: const TextStyle(fontSize: 11, color: kMuted)),
                  ),
                );
              }),
              const SizedBox(height: 30),
            ]),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(zh ? '🏬 仓库 / 门店' : '🏬 Warehouses'),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.add, color: kText), onPressed: () => _addOrRename())],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🏬', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(zh ? '还没有仓库/门店' : 'No warehouses yet', style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: () => _addOrRename(), icon: const Icon(Icons.add),
                label: Text(zh ? '新增仓库/门店' : 'New Warehouse'),
                style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
            ]))
          : ListView(padding: const EdgeInsets.all(16), children: _list.map((wh) {
              final count = _assign.values.where((v) => v == wh['id']).length;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Text('🏬', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(wh['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
                    Text('$count ${zh ? '件物品' : 'items'}', style: const TextStyle(fontSize: 11, color: kMuted)),
                  ])),
                  TextButton(onPressed: () => setState(() => _managing = wh['id'] as int),
                    child: Text(zh ? '分配物品' : 'Assign')),
                  GestureDetector(onTap: () => _addOrRename(wh: wh), child: const Icon(Icons.edit_outlined, size: 20, color: kMuted)),
                  const SizedBox(width: 10),
                  GestureDetector(onTap: () => _delete(wh['id'] as int), child: const Icon(Icons.delete_outline, size: 20, color: kRed)),
                ]),
              );
            }).toList()),
    );
  }
}
