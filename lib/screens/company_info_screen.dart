import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// COMPANY INFO SCREEN
// ════════════════════════════════════════════════════════════════════════════

class CompanyInfoScreen extends StatefulWidget {
  const CompanyInfoScreen({super.key});

  @override
  State<CompanyInfoScreen> createState() => _CompanyInfoScreenState();
}

class _CompanyInfoScreenState extends State<CompanyInfoScreen> {
  final _nameCtrl    = TextEditingController();
  final _tinCtrl     = TextEditingController();
  final _sstCtrl     = TextEditingController();
  final _coRegCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _addrCtrl    = TextEditingController();
  final _bankNmCtrl  = TextEditingController();
  final _bankAcCtrl  = TextEditingController();

  String? _logoB64;
  String? _sigB64;
  bool    _saving = false;
  bool    _dirty  = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _nameCtrl.text   = s.companyName;
    _tinCtrl.text    = s.coTin;
    _sstCtrl.text    = s.sstRegNo;
    _coRegCtrl.text  = s.coReg;
    _phoneCtrl.text  = s.coPhone;
    _emailCtrl.text  = s.coEmail;
    _addrCtrl.text   = s.coAddr;
    _bankNmCtrl.text = s.bankName;
    _bankAcCtrl.text = s.bankAcct;
    _logoB64 = s.logoBase64;
    _sigB64  = s.sigBase64;

    for (final c in [_nameCtrl,_tinCtrl,_sstCtrl,_coRegCtrl,
                     _phoneCtrl,_emailCtrl,_addrCtrl,_bankNmCtrl,_bankAcCtrl]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl,_tinCtrl,_sstCtrl,_coRegCtrl,
                     _phoneCtrl,_emailCtrl,_addrCtrl,_bankNmCtrl,_bankAcCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Image helpers ─────────────────────────────────────────────────────────

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() { _logoB64 = base64Encode(bytes); _dirty = true; });
  }

  Future<void> _pickSig() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() { _sigB64 = base64Encode(bytes); _dirty = true; });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _saving = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final app = context.read<AppState>();
    await app.updateSettings(app.settings.copyWith(
      companyName: _nameCtrl.text.trim(),
      coTin:       _tinCtrl.text.trim(),
      sstRegNo:    _sstCtrl.text.trim(),
      coReg:       _coRegCtrl.text.trim(),
      coPhone:     _phoneCtrl.text.trim(),
      coEmail:     _emailCtrl.text.trim(),
      coAddr:      _addrCtrl.text.trim(),
      bankName:    _bankNmCtrl.text.trim(),
      bankAcct:    _bankAcCtrl.text.trim(),
      logoBase64:  _logoB64,
      sigBase64:   _sigB64,
    ));
    if (mounted) {
      setState(() { _saving = false; _dirty = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Text('✅ ', style: TextStyle(fontSize: 16)),
          Text('Company info saved'),
        ]),
        backgroundColor: kDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: Text(
          lang == 'zh' ? '🏢 公司信息' : '🏢 Company Info',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kDark))
                : Text(
                    lang == 'zh' ? '保存' : 'Save',
                    style: const TextStyle(
                      color: kDark, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Logo + Signature ──────────────────────────────────────────────
          _section(lang == 'zh' ? '图像' : 'Images'),
          Row(children: [
            Expanded(child: _ImageCard(
              label: lang == 'zh' ? 'Company Logo' : 'Company Logo',
              b64: _logoB64,
              onPick: _pickLogo,
              onRemove: () => setState(() { _logoB64 = null; _dirty = true; }),
            )),
            const SizedBox(width: 12),
            Expanded(child: _ImageCard(
              label: lang == 'zh' ? 'Signature' : 'Signature',
              b64: _sigB64,
              onPick: _pickSig,
              onRemove: () => setState(() { _sigB64 = null; _dirty = true; }),
            )),
          ]),

          const SizedBox(height: 20),

          // ── Company Details ───────────────────────────────────────────────
          _section(lang == 'zh' ? '公司资料' : 'Company Details'),

          _field(lang == 'zh' ? 'COMPANY NAME 公司名称' : 'COMPANY NAME',
            TextField(controller: _nameCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec(lang == 'zh' ? '公司名称' : 'e.g. ABC Sdn Bhd'))),

          _field('TIN (MyTax No.)',
            TextField(controller: _tinCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. C12345678900'))),

          _field('SST REG. NO.',
            TextField(controller: _sstCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. W10-1234-56789012'))),

          _field('COMPANY REG NO.',
            TextField(controller: _coRegCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. 202301012345'))),

          _field('PHONE',
            TextField(controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. 0123456789'))),

          _field('EMAIL',
            TextField(controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. hello@company.com'))),

          _field(lang == 'zh' ? 'ADDRESS 地址' : 'ADDRESS',
            TextField(controller: _addrCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. No. 1, Jalan ABC, 50000 Kuala Lumpur'))),

          const SizedBox(height: 8),

          // ── Bank Details ──────────────────────────────────────────────────
          _section(lang == 'zh' ? '银行资料' : 'Bank Details'),

          _field(lang == 'zh' ? 'BANK NAME 银行名称' : 'BANK NAME',
            TextField(controller: _bankNmCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. Maybank / CIMB / Public Bank'))),

          _field(lang == 'zh' ? 'ACCOUNT NO. 账号' : 'ACCOUNT NO.',
            TextField(controller: _bankAcCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. 1234567890'))),

          const SizedBox(height: 24),

          // ── Save Button ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_saving || !_dirty) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kBorder,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    lang == 'zh' ? '保存公司信息' : 'Save Company Info',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
          color: kMuted, letterSpacing: 1)),
  );

  Widget _field(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      child,
    ]),
  );

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 13),
    filled: true, fillColor: kSurface,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kDark, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// IMAGE CARD WIDGET
// ════════════════════════════════════════════════════════════════════════════

class _ImageCard extends StatelessWidget {
  final String  label;
  final String? b64;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ImageCard({
    required this.label,
    required this.b64,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onPick,
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: b64 != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.memory(base64Decode(b64!),
                    fit: BoxFit.contain, width: double.infinity))
            : const Center(child: Icon(Icons.add_photo_alternate_outlined,
                color: kMuted, size: 28)),
        ),
      ),
      if (b64 != null) ...[
        const SizedBox(height: 4),
        GestureDetector(
          onTap: onRemove,
          child: const Text('Remove',
              style: TextStyle(fontSize: 12, color: kRed,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}
