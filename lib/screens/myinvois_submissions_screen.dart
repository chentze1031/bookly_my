import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../services/myinvois_service.dart';
import '../widgets/common.dart' show miEnvBadge;

// MyInvois consolidated (B2C) submissions — status / 72h cancel / validation QR.
// Records are saved device-locally when a consolidated e-Invoice is submitted.
class MyInvoisSubmissionsScreen extends StatefulWidget {
  const MyInvoisSubmissionsScreen({super.key});
  @override
  State<MyInvoisSubmissionsScreen> createState() => _MyInvoisSubmissionsScreenState();
}

class _MyInvoisSubmissionsScreenState extends State<MyInvoisSubmissionsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _busyId; // submissionUid currently processing

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final list = await context.read<AppState>().loadConsolidated();
    if (mounted) setState(() { _items = list; _loading = false; });
  }

  Future<void> _refresh(Map<String, dynamic> r) async {
    final sid = r['submissionUid'] as String?;
    if (sid == null) return;
    setState(() => _busyId = sid);
    final res = await MyInvoisService.checkStatus(sid);
    await context.read<AppState>().updateConsolidated(sid, {
      'status': res.status,
      if (res.uuid != null) 'uuid': res.uuid,
      if (res.longId != null) 'longId': res.longId,
    });
    if (mounted) setState(() => _busyId = null);
    await _load();
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final uuid = r['uuid'] as String?;
    final sid = r['submissionUid'] as String?;
    if (uuid == null || sid == null) return;
    final lang = context.read<AppState>().settings.lang;
    final reason = await _askReason(lang);
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busyId = sid);
    final res = await MyInvoisService.cancelInvoice(uuid, reason.trim());
    if (res.ok) {
      await context.read<AppState>().updateConsolidated(sid, {'status': 'Cancelled'});
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Cancel failed'), backgroundColor: kRed));
    }
    if (mounted) setState(() => _busyId = null);
    await _load();
  }

  Future<String?> _askReason(String lang) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(tr(lang, 'Cancellation reason', '取消原因', 'Sebab pembatalan'),
            style: TextStyle(color: kText, fontSize: 16)),
        content: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: kText),
          decoration: InputDecoration(hintText: tr(lang, 'Reason', '原因', 'Sebab'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(lang, 'Cancel', '取消', 'Batal'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr(lang, 'OK', '确定', 'OK'))),
        ],
      ),
    );
  }

  void _showQr(Map<String, dynamic> r, String lang) {
    final url = MyInvoisService.validationUrl(
        (r['env'] ?? 'sandbox').toString(), r['uuid'] as String, r['longId'] as String);
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kSurface,
      title: Text(r['consNo']?.toString() ?? 'QR', style: TextStyle(color: kText, fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.white,
          child: QrImageView(data: url, version: QrVersions.auto, size: 200,
              backgroundColor: Colors.white),
        ),
        const SizedBox(height: 10),
        SelectableText(url, style: const TextStyle(fontSize: 10, color: kMuted)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: Text(tr(lang, 'Close', '关闭', 'Tutup')))],
    ));
  }

  ({Color c, String label}) _statusBadge(String s, String lang) => switch (s) {
    'Valid'      => (c: kGreen, label: tr(lang, 'Validated', '已验证', 'Disahkan')),
    'Invalid'    => (c: kRed,   label: tr(lang, 'Invalid', '无效', 'Tidak Sah')),
    'InProgress' => (c: kGold,  label: tr(lang, 'In progress', '处理中', 'Diproses')),
    'Cancelled'  => (c: kMuted, label: tr(lang, 'Cancelled', '已取消', 'Dibatalkan')),
    _            => (c: kMuted, label: s),
  };

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Consolidated e-Invoices', 'MyInvois 提交记录', 'e-Invois Disatukan')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(
                  tr(lang, 'No consolidated submissions yet.', '还没有合并发票提交记录。', 'Tiada penghantaran disatukan.'),
                  style: const TextStyle(color: kMuted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final r = _items[i];
                      final status = (r['status'] ?? 'InProgress').toString();
                      final b = _statusBadge(status, lang);
                      final sid = r['submissionUid'] as String?;
                      final busy = _busyId != null && _busyId == sid;
                      final canCancel = status == 'Valid' && r['uuid'] != null;
                      final canQr = status == 'Valid' && r['uuid'] != null && r['longId'] != null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kSurface,
                            border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(r['consNo']?.toString() ?? '—',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText))),
                            miEnvBadge(r['env'] as String?),
                            const SizedBox(width: 6),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: b.c.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: b.c.withValues(alpha: 0.4))),
                              child: Text(b.label, style: TextStyle(color: b.c, fontSize: 11, fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 6),
                          Text('${tr(lang, 'Month', '月份', 'Bulan')}: ${r['month'] ?? '—'} · '
                               '${r['count'] ?? 0} ${tr(lang, 'invoices', '张发票', 'invois')}',
                              style: const TextStyle(fontSize: 12, color: kMuted)),
                          if (r['uuid'] != null) ...[
                            const SizedBox(height: 4),
                            SelectableText('UUID: ${r['uuid']}', style: const TextStyle(fontSize: 10, color: kMuted)),
                          ],
                          const SizedBox(height: 10),
                          if (busy)
                            const Center(child: SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2)))
                          else
                            Row(children: [
                              if (status == 'InProgress' || status == 'Valid')
                                OutlinedButton.icon(onPressed: () => _refresh(r),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(tr(lang, 'Status', '查状态', 'Status'))),
                              if (canQr) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(onPressed: () => _showQr(r, lang),
                                  icon: const Icon(Icons.qr_code, size: 16), label: const Text('QR')),
                              ],
                              if (canCancel) ...[
                                const Spacer(),
                                TextButton(onPressed: () => _cancel(r),
                                  child: Text(tr(lang, 'Cancel e-Invoice', '取消发票', 'Batal'),
                                      style: TextStyle(color: kRed))),
                              ],
                            ]),
                          if (canCancel)
                            Padding(padding: const EdgeInsets.only(top: 2),
                              child: Text(tr(lang,
                                  'Cancellation only within 72h of validation.',
                                  '仅可在验证后 72 小时内取消。',
                                  'Pembatalan hanya dalam 72 jam selepas pengesahan.'),
                                  style: const TextStyle(fontSize: 10, color: kMuted))),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
