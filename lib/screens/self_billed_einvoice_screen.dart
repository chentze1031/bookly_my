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
// Self-billed e-Invoice (Phase 4 #28 v2, D2)
//
// For cases where the BUYER issues the e-Invoice on the supplier's behalf
// (foreign suppliers, payments to agents/individuals, etc.). Document type 11:
// the counterparty becomes the supplier, your company is the buyer. Foreign
// suppliers without a Malaysian TIN use the general foreign TIN EI00000000020.
// ════════════════════════════════════════════════════════════════════════════

Future<void> showSelfBilledSheet(BuildContext context) =>
    showAppSheet(context: context, fullHeight: true, child: const SelfBilledSheet());

class SelfBilledSheet extends StatefulWidget {
  const SelfBilledSheet({super.key});
  @override
  State<SelfBilledSheet> createState() => _SelfBilledSheetState();
}

class _SelfBilledSheetState extends State<SelfBilledSheet> {
  final _name = TextEditingController();
  final _tin = TextEditingController();
  final _brn = TextEditingController();
  final _addr = TextEditingController();
  final _phone = TextEditingController(); // supplier phone (LHDN CF414: ≥8 chars)
  final _msic = TextEditingController();  // supplier MSIC (LHDN CF360)
  String _state = '17';
  final List<({TextEditingController desc, TextEditingController amt})> _lines = [
    (desc: TextEditingController(), amt: TextEditingController()),
  ];
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in [_name, _tin, _brn, _addr, _phone, _msic]) {
      c.dispose();
    }
    for (final l in _lines) { l.desc.dispose(); l.amt.dispose(); }
    super.dispose();
  }

  double get _total => _lines.fold(0.0, (a, l) => a + (double.tryParse(l.amt.text) ?? 0));

  Future<void> _submit(String lang) async {
    final sub = context.read<SubState>();
    if (!sub.isPro) { showSubSheet(context); return; }
    final app = context.read<AppState>();
    final items = <Map<String, dynamic>>[];
    for (final l in _lines) {
      final amt = double.tryParse(l.amt.text) ?? 0;
      if (amt <= 0) continue;
      items.add({'desc': l.desc.text.trim().isEmpty ? 'Item' : l.desc.text.trim(),
                 'qty': '1', 'price': '$amt', 'sst': 'none'});
    }
    if (_name.text.trim().isEmpty || items.isEmpty) {
      setState(() { _ok = false; _result = tr(lang,
        'Enter the supplier name and at least one line.',
        '请填写供应商名称和至少一行金额。',
        'Masukkan nama pembekal dan sekurang-kurangnya satu baris.'); });
      return;
    }
    setState(() { _busy = true; _result = null; });
    // LHDN requires a valid supplier phone (≥8) + MSIC; fall back to the
    // company's own (valid) values when the user leaves them blank.
    final supPhone = _phone.text.trim().isNotEmpty ? _phone.text.trim() : app.settings.coPhone;
    final supMsic  = _msic.text.trim().isNotEmpty  ? _msic.text.trim()  : app.settings.msicCode;
    final counterparty = Customer(
      id: 0, name: _name.text.trim(), tin: _tin.text.trim(),
      regNo: _brn.text.trim(), address: _addr.text.trim(), state: _state,
      phone: supPhone);
    final invNo = 'SB-${DateTime.now().millisecondsSinceEpoch}';
    final invoice = {
      'invNo': invNo,
      'invDate': DateTime.now().toIso8601String().substring(0, 10),
      'items': items,
    };
    final r = await MyInvoisService.submitSelfBilled(
      counterparty: counterparty, invoice: invoice, supplier: app.settings,
      supplierMsic: supMsic, supplierMsicDesc: app.settings.msicDesc);
    if (mounted) setState(() {
      _busy = false; _ok = r.ok;
      _result = r.ok
        ? tr(lang, 'Submitted ($invNo). Status: In progress.',
                '已提交（$invNo）。状态：处理中。',
                'Dihantar ($invNo). Status: Diproses.')
        : (r.error ?? tr(lang, 'Submit failed', '提交失败', 'Gagal hantar'));
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final loggedIn = MyInvoisService.isLoggedIn;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Row(children: [
          Expanded(child: Text(
            tr(lang, 'Self-billed e-Invoice', '自开发票', 'e-Invois Layan Diri'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText))),
          IconButton(icon: Icon(Icons.close, color: kMuted), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      Expanded(
        child: !loggedIn
          ? Padding(padding: const EdgeInsets.all(20),
              child: Text(tr(lang, 'Sign in + configure MyInvois first.',
                '请先登录并配置 MyInvois。', 'Log masuk + konfigur MyInvois dahulu.'),
                style: const TextStyle(color: kMuted)))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(lang,
                  'For payments where you issue on the supplier\'s behalf (e.g. foreign suppliers, agents). The supplier below is the counterparty; your company is the buyer.',
                  '用于由你代供应商开具的付款（如外国供应商、代理）。下方“供应商”为对方；本公司为买方。',
                  'Untuk bayaran yang anda keluarkan bagi pihak pembekal (cth. pembekal asing, ejen). "Pembekal" di bawah ialah pihak lawan; syarikat anda ialah pembeli.'),
                  style: const TextStyle(fontSize: 12, color: kMuted)),
                const SizedBox(height: 14),

                _ctrlField(tr(lang, 'Supplier name', '供应商名称', 'Nama pembekal'), _name),
                _ctrlField(tr(lang, 'Supplier TIN (blank = foreign EI00000000020)', '供应商 TIN（留空=外国 EI00000000020）', 'TIN pembekal (kosong = asing EI00000000020)'), _tin),
                _ctrlField(tr(lang, 'Supplier BRN (optional)', '供应商注册号（可选）', 'BRN pembekal (pilihan)'), _brn),
                _ctrlField(tr(lang, 'Supplier address', '供应商地址', 'Alamat pembekal'), _addr),
                _ctrlField(tr(lang, 'Supplier phone (blank = use yours)', '供应商电话（留空=用本公司）', 'Telefon pembekal (kosong = guna anda)'), _phone),
                _ctrlField(tr(lang, 'Supplier MSIC (blank = use yours)', '供应商 MSIC（留空=用本公司）', 'MSIC pembekal (kosong = guna anda)'), _msic),
                StateDropdown(lang: lang, value: _state, onChanged: (v) => setState(() => _state = v)),

                const SizedBox(height: 6),
                Text(tr(lang, 'LINES', '行项', 'BARIS'),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: .5)),
                const SizedBox(height: 6),
                for (var i = 0; i < _lines.length; i++) _lineRow(lang, i),
                TextButton.icon(
                  onPressed: () => setState(() => _lines.add(
                    (desc: TextEditingController(), amt: TextEditingController()))),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr(lang, 'Add line', '加一行', 'Tambah baris')),
                ),

                if (_result != null) ...[
                  const SizedBox(height: 8),
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
      if (loggedIn)
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: Text('RM ${_total.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText))),
            ElevatedButton(
              onPressed: _busy ? null : () => _submit(lang),
              style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
              child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(tr(lang, 'Submit self-billed', '提交自开发票', 'Hantar layan diri')),
            ),
          ]),
        )),
    ]);
  }

  Widget _ctrlField(String label, TextEditingController c) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: .5)),
      const SizedBox(height: 4),
      TextField(controller: c, style: TextStyle(fontSize: 14, color: kText),
        decoration: InputDecoration(
          isDense: true, filled: true, fillColor: kBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: kBorder, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: kBorder, width: 1.5)),
        )),
    ]),
  );

  Widget _lineRow(String lang, int i) {
    final l = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(flex: 3, child: TextField(controller: l.desc,
          style: TextStyle(fontSize: 13, color: kText),
          decoration: InputDecoration(isDense: true, hintText: tr(lang, 'Description', '描述', 'Keterangan'),
            hintStyle: const TextStyle(color: kMuted, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kBorder))))),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: TextField(controller: l.amt,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: TextStyle(fontSize: 13, color: kText),
          decoration: InputDecoration(isDense: true, hintText: 'RM',
            hintStyle: const TextStyle(color: kMuted, fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kBorder))))),
        if (_lines.length > 1)
          IconButton(icon: Icon(Icons.remove_circle_outline, size: 20, color: kMuted),
            onPressed: () => setState(() { _lines[i].desc.dispose(); _lines[i].amt.dispose(); _lines.removeAt(i); })),
      ]),
    );
  }
}
