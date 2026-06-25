import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

import '../constants.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// DATA BACKUP & RESTORE  (full per-company export/restore, FREE)
// ════════════════════════════════════════════════════════════════════════════
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  String get _lang => context.read<AppState>().settings.lang;

  // ── Shared file helper ───────────────────────────────────────────────────
  Future<void> _shareFile(List<int> bytes, String name, String mime) async {
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path, mimeType: mime)], subject: name);
    if (mounted) context.read<SubState>().onShareAction();
  }

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_').replaceAll(RegExp(r'_+'), '_');

  // ── Export: full JSON backup ─────────────────────────────────────────────
  Future<void> _exportJson() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final data  = app.buildBackup();
      final json  = const JsonEncoder.withIndent('  ').convert(data);
      final co    = _safeName(app.activeCompanyObj.name);
      final date  = DateFormat('yyyyMMdd').format(DateTime.now());
      await _shareFile(utf8.encode(json), 'Bookly_Backup_${co}_$date.json', 'application/json');
    } catch (e) {
      _toast(tr(_lang, 'Export failed', '导出失败', 'Eksport gagal'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Export: CSV (Excel-openable) ─────────────────────────────────────────
  Future<void> _exportCsv() async {
    final app  = context.read<AppState>();
    final lang = app.settings.lang;
    setState(() => _busy = true);
    try {
      final sorted = [...app.txs]..sort((a, b) => b.date.compareTo(a.date));
      String esc(String s) => s.replaceAll(',', ' ').replaceAll('\n', ' ');
      final buf = StringBuffer();
      buf.writeln('Date,Type,Category,Description,Amount (MYR),SST (MYR)');
      for (final tx in sorted) {
        final cat  = findCat(tx.catId)?.label(lang) ?? tx.catId;
        final desc = lang == 'zh' ? tx.descZH : tx.descEN;
        buf.writeln('${tx.date},${tx.type},${esc(cat)},${esc(desc)},'
            '${tx.amountMYR.toStringAsFixed(2)},${tx.sstMYR.toStringAsFixed(2)}');
      }
      final co   = _safeName(app.activeCompanyObj.name);
      final date = DateFormat('yyyyMMdd').format(DateTime.now());
      await _shareFile(utf8.encode(buf.toString()), 'Bookly_Transactions_${co}_$date.csv', 'text/csv');
    } catch (e) {
      _toast(tr(_lang, 'Export failed', '导出失败', 'Eksport gagal'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Restore from a JSON backup file ──────────────────────────────────────
  Future<void> _restore() async {
    final app  = context.read<AppState>();
    final lang = app.settings.lang;
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final f = picked.files.single;
      String raw;
      if (f.bytes != null) {
        raw = utf8.decode(f.bytes!);
      } else if (f.path != null) {
        raw = await File(f.path!).readAsString();
      } else {
        _toast(tr(lang, 'Could not read file', '无法读取文件', 'Tidak dapat membaca fail'));
        return;
      }

      final map = jsonDecode(raw);
      if (map is! Map || map['app'] != 'bookly_my') {
        _toast(tr(lang, 'Not a valid Bookly backup', '不是有效的 Bookly 备份', 'Bukan sandaran Bookly yang sah'));
        return;
      }
      final data = Map<String, dynamic>.from(map);
      final txN  = (data['transactions'] as List?)?.length ?? 0;
      final cuN  = (data['customers']    as List?)?.length ?? 0;
      final emN  = (data['employees']    as List?)?.length ?? 0;
      final from = (data['companyName'] as String?)?.trim();

      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(tr(lang, 'Restore backup?', '恢复备份？', 'Pulihkan sandaran?'),
              style: TextStyle(color: kText, fontWeight: FontWeight.w800, fontSize: 16)),
          content: Text(
            tr(lang,
              'This will import $txN transactions, $cuN customers and $emN employees'
                  '${from != null && from.isNotEmpty ? ' from "$from"' : ''} into the current company '
                  '"${app.activeCompanyObj.name}". Existing records with the same ID will be overwritten.',
              '将把 $txN 笔交易、$cuN 个客户、$emN 名员工'
                  '${from != null && from.isNotEmpty ? '（来自“$from”）' : ''}导入当前公司'
                  '“${app.activeCompanyObj.name}”。相同 ID 的现有记录将被覆盖。',
              'Ini akan mengimport $txN transaksi, $cuN pelanggan dan $emN pekerja'
                  '${from != null && from.isNotEmpty ? ' dari "$from"' : ''} ke syarikat semasa '
                  '"${app.activeCompanyObj.name}". Rekod sedia ada dengan ID sama akan ditimpa.'),
            style: TextStyle(color: kText, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr(lang, 'Cancel', '取消', 'Batal'), style: const TextStyle(color: kMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(lang, 'Restore', '恢复', 'Pulihkan'),
                  style: TextStyle(color: kPro, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (ok != true) return;

      final counts = await app.restoreFromBackup(data);
      _toast(tr(lang,
        'Restored ${counts['transactions']} transactions, ${counts['customers']} customers, ${counts['employees']} employees',
        '已恢复 ${counts['transactions']} 笔交易、${counts['customers']} 个客户、${counts['employees']} 名员工',
        'Dipulihkan ${counts['transactions']} transaksi, ${counts['customers']} pelanggan, ${counts['employees']} pekerja'));
    } catch (e) {
      _toast(tr(_lang, 'Restore failed — invalid file', '恢复失败 — 文件无效', 'Pemulihan gagal — fail tidak sah'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Backup & Restore', '备份与恢复', 'Sandaran & Pulih')),
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _intro(lang),
          const SizedBox(height: 12),
          _card(
            emoji: '💾',
            title: tr(lang, 'Export full backup (JSON)', '导出完整备份（JSON）', 'Eksport sandaran penuh (JSON)'),
            subtitle: tr(lang,
              'Save all transactions, customers & employees to a file you can restore later',
              '将所有交易、客户和员工保存为可日后恢复的文件',
              'Simpan semua transaksi, pelanggan & pekerja ke fail untuk dipulihkan kemudian'),
            onTap: _exportJson,
          ),
          _card(
            emoji: '📊',
            title: tr(lang, 'Export transactions (CSV)', '导出交易（CSV）', 'Eksport transaksi (CSV)'),
            subtitle: tr(lang,
              'Open in Excel or Google Sheets',
              '可用 Excel 或 Google 表格打开',
              'Buka dalam Excel atau Google Sheets'),
            onTap: _exportCsv,
          ),
          _card(
            emoji: '♻️',
            title: tr(lang, 'Restore from backup', '从备份恢复', 'Pulihkan dari sandaran'),
            subtitle: tr(lang,
              'Pick a Bookly JSON backup file to import',
              '选择一个 Bookly JSON 备份文件导入',
              'Pilih fail sandaran JSON Bookly untuk diimport'),
            onTap: _restore,
          ),
          const SizedBox(height: 18),
          _card(
            emoji: '⭐',
            title: tr(lang, 'Rate Bookly', '给 Bookly 评分', 'Nilai Bookly'),
            subtitle: tr(lang,
              'Enjoying the app? Leave us a review',
              '喜欢这个应用？给我们留个评价吧',
              'Suka aplikasi ini? Tinggalkan ulasan'),
            onTap: () => context.read<AppState>().openStoreListing(),
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Widget _intro(String lang) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kBlueBg,
      border: Border.all(color: kBlueBd),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      tr(lang,
        'Your data is stored on this device. Export a backup regularly so you never lose it — and use it to move to a new phone.',
        '您的数据保存在本设备上。请定期导出备份以防丢失，也可用于更换新手机。',
        'Data anda disimpan pada peranti ini. Eksport sandaran secara berkala supaya tidak hilang — dan gunakannya untuk berpindah ke telefon baharu.'),
      style: TextStyle(color: kText, fontSize: 12.5, height: 1.45),
    ),
  );

  Widget _card({
    required String emoji,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: kSurface,
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Text(emoji, style: const TextStyle(fontSize: 24)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kText)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: kMuted)),
      trailing: const Icon(Icons.chevron_right, color: kMuted),
      onTap: _busy ? null : onTap,
    ),
  );
}
