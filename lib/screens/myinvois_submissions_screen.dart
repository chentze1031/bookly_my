import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../services/myinvois_service.dart';
import '../widgets/common.dart' show miEnvBadge;

// All MyInvois submissions in one place — regular invoices AND consolidated
// (B2C) documents — each with status / 72h cancel / validation QR.
class MyInvoisSubmissionsScreen extends StatefulWidget {
  const MyInvoisSubmissionsScreen({super.key});
  @override
  State<MyInvoisSubmissionsScreen> createState() => _MyInvoisSubmissionsScreenState();
}

class _MyInvoisSubmissionsScreenState extends State<MyInvoisSubmissionsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _busyId;

  String _idOf(Map<String, dynamic> r) => '${r['kind']}:${r['title']}';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final items = <Map<String, dynamic>>[];
    // Consolidated (B2C) submissions.
    for (final c in await app.loadConsolidated()) {
      items.add({
        'kind': 'consolidated',
        'title': (c['consNo'] ?? '—').toString(),
        'subtitle': '${c['month'] ?? ''} · ${c['count'] ?? 0}',
        'uuid': c['uuid'], 'submissionUid': c['submissionUid'], 'longId': c['longId'],
        'status': (c['status'] ?? 'InProgress').toString(), 'env': c['env'],
        'date': (c['createdAt'] ?? '').toString(),
      });
    }
    // Regular invoices that were actually submitted to MyInvois.
    for (final inv in await app.loadInvoices()) {
      final st = (inv['miStatus'] ?? 'none').toString();
      if (st == 'none' || st == 'Consolidated') continue; // not individually submitted
      items.add({
        'kind': 'invoice',
        'title': (inv['invNo'] ?? '—').toString(),
        'subtitle': ((inv['customer'] as Map?)?['name'] ?? '').toString(),
        'uuid': inv['miUuid'], 'submissionUid': inv['miSubmissionUid'], 'longId': inv['miLongId'],
        'status': st, 'env': inv['miEnv'],
        'date': (inv['invDate'] ?? '').toString(), 'invNo': inv['invNo'],
      });
    }
    items.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _refresh(Map<String, dynamic> r) async {
    final sid = r['submissionUid'] as String?;
    if (sid == null) return;
    setState(() => _busyId = _idOf(r));
    final res = await MyInvoisService.checkStatus(sid);
    final app = context.read<AppState>();
    if (r['kind'] == 'consolidated') {
      await app.updateConsolidated(sid, {
        'status': res.status,
        if (res.uuid != null) 'uuid': res.uuid,
        if (res.longId != null) 'longId': res.longId,
      });
    } else {
      await app.updateInvoiceMyInvois((r['invNo'] ?? '').toString(), {
        'miStatus': res.status,
        if (res.uuid != null) 'miUuid': res.uuid,
        if (res.longId != null) 'miLongId': res.longId,
      });
    }
    if (mounted) setState(() => _busyId = null);
    await _load();
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final uuid = r['uuid'] as String?;
    if (uuid == null) return;
    final lang = context.read<AppState>().settings.lang;
    final reason = await _askReason(lang);
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busyId = _idOf(r));
    final res = await MyInvoisService.cancelInvoice(uuid, reason.trim());
    final app = context.read<AppState>();
    if (res.ok) {
      if (r['kind'] == 'consolidated') {
        await app.updateConsolidated((r['submissionUid'] ?? '').toString(), {'status': 'Cancelled'});
      } else {
        await app.updateInvoiceMyInvois((r['invNo'] ?? '').toString(), {'miStatus': 'Cancelled'});
      }
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
    showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: kSurface,
      title: Text(r['title']?.toString() ?? 'QR', style: TextStyle(color: kText, fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(10), color: Colors.white,
          child: QrImageView(data: url, version: QrVersions.auto, size: 200, backgroundColor: Colors.white)),
        const SizedBox(height: 10),
        SelectableText(url, style: const TextStyle(fontSize: 10, color: kMuted)),
      ]),
      // Pop the dialog's own context (not the page's), else "Close" pops the
      // records page and leaves the dialog on screen.
      actions: [TextButton(onPressed: () => Navigator.pop(dialogCtx),
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
        title: Text(tr(lang, 'MyInvois Records', 'MyInvois 记录', 'Rekod MyInvois')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(
                  tr(lang, 'No MyInvois submissions yet.', '还没有 MyInvois 提交记录。', 'Tiada penghantaran MyInvois.'),
                  style: const TextStyle(color: kMuted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final r = _items[i];
                      final status = r['status'].toString();
                      final b = _statusBadge(status, lang);
                      final busy = _busyId == _idOf(r);
                      final isCons = r['kind'] == 'consolidated';
                      final canCancel = status == 'Valid' && r['uuid'] != null;
                      final canQr = status == 'Valid' && r['uuid'] != null && r['longId'] != null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kSurface,
                            border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(r['title'].toString(),
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText))),
                            miEnvBadge(r['env'] as String?),
                            const SizedBox(width: 6),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: b.c.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: b.c.withValues(alpha: 0.4))),
                              child: Text(b.label, style: TextStyle(color: b.c, fontSize: 11, fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: (isCons ? kBlue : kMuted).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(isCons ? tr(lang, 'Consolidated', '合并', 'Disatukan') : tr(lang, 'Invoice', '发票', 'Invois'),
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isCons ? kBlue : kMuted))),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r['subtitle'].toString(),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: kMuted))),
                          ]),
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
                                  child: Text(tr(lang, 'Cancel', '取消', 'Batal'), style: TextStyle(color: kRed))),
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
