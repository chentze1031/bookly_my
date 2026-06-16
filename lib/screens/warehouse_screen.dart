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
    final lang = context.read<AppState>().settings.lang;
    final name = await showDialog<String>(context: context, builder: (dctx) => AlertDialog(
      title: Text(wh == null
          ? tr(lang, 'New Warehouse', '新增仓库/门店', 'Gudang Baharu')
          : tr(lang, 'Rename', '重命名', 'Namakan Semula')),
      content: TextField(controller: ctrl, autofocus: true,
        onSubmitted: (v) => Navigator.pop(dctx, v.trim()),
        decoration: InputDecoration(hintText: tr(lang, 'Name', '名称', 'Nama'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr(lang, 'Cancel', '取消', 'Batal'))),
        TextButton(onPressed: () => Navigator.pop(dctx, ctrl.text.trim()), child: Text(tr(lang, 'Save', '保存', 'Simpan'))),
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
    final lang = context.watch<AppState>().settings.lang;
    final inv = context.watch<InventoryState>();

    if (_managing != null) {
      final wh = _list.firstWhere((w) => w['id'] == _managing, orElse: () => {'id': _managing, 'name': ''});
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(
          backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _managing = null)),
          title: Text('${tr(lang, 'Assign', '分配物品', 'Tetapkan')} · ${wh['name']}'),
        ),
        body: inv.items.isEmpty
          ? Center(child: Text(tr(lang, 'No inventory items', '暂无库存物品', 'Tiada item inventori'), style: const TextStyle(color: kMuted)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(tr(lang, 'Tick items in this warehouse (one warehouse per item)', '勾选属于本仓库的物品（一个物品只能在一个仓库）', 'Tanda item dalam gudang ini (satu gudang setiap item)'),
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
                    title: Text(it.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
                    subtitle: Text([
                      if (it.sku.isNotEmpty) it.sku,
                      '${tr(lang, 'Qty', '库存', 'Kuantiti')} ${it.qty % 1 == 0 ? it.qty.toInt() : it.qty}',
                      if (elsewhere != null) '${tr(lang, 'in', '现属', 'di')}: $elsewhere',
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
        title: Text(tr(lang, '🏬 Warehouses', '🏬 仓库 / 门店', '🏬 Gudang / Kedai')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
        actions: [IconButton(icon: Icon(Icons.add, color: kText), onPressed: () => _addOrRename())],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : _list.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🏬', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(tr(lang, 'No warehouses yet', '还没有仓库/门店', 'Belum ada gudang'), style: const TextStyle(color: kMuted, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: () => _addOrRename(), icon: const Icon(Icons.add),
                label: Text(tr(lang, 'New Warehouse', '新增仓库/门店', 'Gudang Baharu')),
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
                    Text(wh['name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
                    Text('$count ${tr(lang, 'items', '件物品', 'item')}', style: const TextStyle(fontSize: 11, color: kMuted)),
                  ])),
                  TextButton(onPressed: () => setState(() => _managing = wh['id'] as int),
                    child: Text(tr(lang, 'Assign', '分配物品', 'Tetapkan'))),
                  GestureDetector(onTap: () => _addOrRename(wh: wh), child: const Icon(Icons.edit_outlined, size: 20, color: kMuted)),
                  const SizedBox(width: 10),
                  GestureDetector(onTap: () => _delete(wh['id'] as int), child: Icon(Icons.delete_outline, size: 20, color: kRed)),
                ]),
              );
            }).toList()),
    );
  }
}
