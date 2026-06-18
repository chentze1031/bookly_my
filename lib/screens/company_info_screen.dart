import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart' show StateDropdown;

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
  final _cityCtrl    = TextEditingController();
  final _postCtrl    = TextEditingController();
  final _bankNmCtrl  = TextEditingController();
  final _bankAcCtrl  = TextEditingController();
  String _state = '17';
  String _regType = 'BRN'; // BRN | NRIC | PASSPORT | ARMY

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
    _cityCtrl.text   = s.coCity;
    _postCtrl.text   = s.coPostcode;
    _state           = s.coState.isEmpty ? '17' : s.coState;
    _regType         = s.regType.isEmpty ? 'BRN' : s.regType;
    _bankNmCtrl.text = s.bankName;
    _bankAcCtrl.text = s.bankAcct;
    _logoB64 = s.logoBase64;
    _sigB64  = s.sigBase64;

    for (final c in [_nameCtrl,_tinCtrl,_sstCtrl,_coRegCtrl,
                     _phoneCtrl,_emailCtrl,_addrCtrl,_cityCtrl,_postCtrl,
                     _bankNmCtrl,_bankAcCtrl]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl,_tinCtrl,_sstCtrl,_coRegCtrl,
                     _phoneCtrl,_emailCtrl,_addrCtrl,_cityCtrl,_postCtrl,
                     _bankNmCtrl,_bankAcCtrl]) {
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
      coCity:      _cityCtrl.text.trim(),
      coPostcode:  _postCtrl.text.trim(),
      coState:     _state,
      regType:     _regType,
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
          tr(lang, '🏢 Company Info', '🏢 公司信息', '🏢 Maklumat Syarikat'),
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kText),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_dirty)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kText))
                : Text(
                    tr(lang, 'Save', '保存', 'Simpan'),
                    style: TextStyle(
                      color: kText, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Logo + Signature ──────────────────────────────────────────────
          _section(tr(lang, 'Images', '图像', 'Imej')),
          Row(children: [
            Expanded(child: _ImageCard(
              label: tr(lang, 'Company Logo', '公司 Logo', 'Logo Syarikat'),
              b64: _logoB64,
              onPick: _pickLogo,
              onRemove: () => setState(() { _logoB64 = null; _dirty = true; }),
            )),
            const SizedBox(width: 12),
            Expanded(child: _ImageCard(
              label: tr(lang, 'Signature', '签名', 'Tandatangan'),
              b64: _sigB64,
              onPick: _pickSig,
              onRemove: () => setState(() { _sigB64 = null; _dirty = true; }),
            )),
          ]),

          const SizedBox(height: 20),

          // ── Company Details ───────────────────────────────────────────────
          _section(tr(lang, 'Company Details', '公司资料', 'Butiran Syarikat')),

          _field(tr(lang, 'COMPANY NAME', 'COMPANY NAME 公司名称', 'NAMA SYARIKAT'),
            TextField(controller: _nameCtrl,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec(tr(lang, 'e.g. ABC Sdn Bhd', '公司名称', 'cth. ABC Sdn Bhd')))),

          _field('TIN (MyTax No.)',
            TextField(controller: _tinCtrl,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. C12345678900'))),

          _field('SST REG. NO.',
            TextField(controller: _sstCtrl,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. W10-1234-56789012'))),

          // Registration ID: companies use BRN; individuals/sole proprietors
          // MUST use NRIC (MyKad) — LHDN validates TIN + this number together.
          _field(tr(lang, 'REGISTRATION ID (BRN / NRIC)', '登记号 (BRN 公司 / NRIC 个人)', 'ID PENDAFTARAN (BRN / NRIC)'),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _regType, dropdownColor: kSurface,
                    style: TextStyle(fontSize: 13, color: kText),
                    items: const [
                      DropdownMenuItem(value: 'BRN', child: Text('BRN')),
                      DropdownMenuItem(value: 'NRIC', child: Text('NRIC')),
                      DropdownMenuItem(value: 'PASSPORT', child: Text('Passport')),
                      DropdownMenuItem(value: 'ARMY', child: Text('Army')),
                    ],
                    onChanged: (v) => setState(() { _regType = v ?? 'BRN'; _dirty = true; }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _coRegCtrl,
                style: TextStyle(fontSize: 14, color: kText),
                decoration: _dec(_regType == 'NRIC' ? 'MyKad e.g. 900101011234' : 'e.g. 202301012345'))),
            ])),

          _field('PHONE',
            TextField(controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. 0123456789'))),

          _field('EMAIL',
            TextField(controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. hello@company.com'))),

          _field(tr(lang, 'ADDRESS', 'ADDRESS 地址', 'ALAMAT'),
            TextField(controller: _addrCtrl,
              maxLines: 3,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. No. 1, Jalan ABC'))),

          Row(children: [
            Expanded(child: _field(tr(lang, 'CITY', '城市', 'BANDAR'),
              TextField(controller: _cityCtrl,
                style: TextStyle(fontSize: 14, color: kText),
                decoration: _dec('e.g. Kuala Lumpur')))),
            const SizedBox(width: 12),
            Expanded(child: _field(tr(lang, 'POSTCODE', '邮编', 'POSKOD'),
              TextField(controller: _postCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 14, color: kText),
                decoration: _dec('e.g. 50000')))),
          ]),

          // MyInvois state code (used in the e-Invoice UBL address).
          StateDropdown(
            lang: lang, value: _state,
            onChanged: (v) => setState(() { _state = v; _dirty = true; })),

          const SizedBox(height: 8),

          // ── Bank Details ──────────────────────────────────────────────────
          _section(tr(lang, 'Bank Details', '银行资料', 'Butiran Bank')),

          _field(tr(lang, 'BANK NAME', 'BANK NAME 银行名称', 'NAMA BANK'),
            TextField(controller: _bankNmCtrl,
              style: TextStyle(fontSize: 14, color: kText),
              decoration: _dec('e.g. Maybank / CIMB / Public Bank'))),

          _field(tr(lang, 'ACCOUNT NO.', 'ACCOUNT NO. 账号', 'NO. AKAUN'),
            TextField(controller: _bankAcCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(fontSize: 14, color: kText),
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
                    tr(lang, 'Save Company Info', '保存公司信息', 'Simpan Maklumat Syarikat'),
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
        borderSide: BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kBorder)),
    focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kDark, width: 1.5)),
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
            // Uploaded logo/signature are designed for white paper (black ink /
            // dark marks). Back them with white even in dark mode so they stay
            // visible; the empty placeholder keeps the themed surface.
            color: b64 != null ? const Color(0xFFFAFAF8) : kSurface,
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
          child: Text('Remove',
              style: TextStyle(fontSize: 12, color: kRed,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}
