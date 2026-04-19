import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../utils/invoice_pdf.dart';
import '../services/db_service.dart';
import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../utils.dart';
import '../widgets/common.dart';

// ─── Public shared helpers (used by payroll_screen.dart too) ──────────────────

class SheetHandle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SheetHandle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
    decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder))),
    child: Column(children: [
      Center(
          child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(99)))),
      const SizedBox(height: 10),
      Row(children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
    ]),
  );
}

class DashedBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const DashedBtn({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
          border: Border.all(color: kBorder, width: 1.5),
          borderRadius: BorderRadius.circular(12)),
      child: Center(
          child:
              Text(label, style: const TextStyle(fontSize: 13, color: kMuted))),
    ),
  );
}

class SmBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color, borderColor, textColor;
  const SmBtn(
      {super.key,
      required this.label,
      required this.onTap,
      this.color,
      this.borderColor,
      this.textColor});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: color ?? kSurface,
          border: Border.all(color: borderColor ?? kBorder),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor ?? kText)),
    ),
  );
}

class EmptyHint extends StatelessWidget {
  final String icon, label;
  const EmptyHint({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(
        child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 44)),
      const SizedBox(height: 10),
      Text(label, style: const TextStyle(color: kMuted, fontSize: 14)),
    ])),
  );
}

// ─── Customer Manager ─────────────────────────────────────────────────────────
class CustomerManagerScreen extends StatefulWidget {
  final void Function(Customer)? onSelect;
  const CustomerManagerScreen({super.key, this.onSelect});

  @override
  State<CustomerManagerScreen> createState() => _CustMgrState();
}

class _CustMgrState extends State<CustomerManagerScreen> {
  Customer? _editing;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = L10n(app.settings.lang);

    if (_editing != null) {
      return _CustEditForm(
        customer: _editing!,
        t: t,
        onSave: (c) async {
          await app.saveCustomer(c);
          setState(() => _editing = null);
        },
        onCancel: () => setState(() => _editing = null),
      );
    }

    return Container(
      decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Column(children: [
        SheetHandle(title: t.customers),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              DashedBtn(
                  label: '+ ${t.newCust}',
                  onTap: () => setState(
                      () => _editing = Customer(id: 0, name: ''))),
              const SizedBox(height: 10),
              if (app.customers.isEmpty)
                const EmptyHint(icon: '👥', label: 'No customers yet'),
              ...app.customers.map((c) => _CustCard(
                    customer: c,
                    onSelect: widget.onSelect != null
                        ? () {
                            widget.onSelect!(c);
                            Navigator.pop(context);
                          }
                        : null,
                    onEdit: () => setState(() => _editing = c),
                    onDelete: () => app.deleteCustomer(c.id),
                  )),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CustEditForm extends StatefulWidget {
  final Customer customer;
  final L10n t;
  final Future<void> Function(Customer) onSave;
  final VoidCallback onCancel;
  const _CustEditForm(
      {required this.customer,
      required this.t,
      required this.onSave,
      required this.onCancel});

  @override
  State<_CustEditForm> createState() => _CustEditFormState();
}

class _CustEditFormState extends State<_CustEditForm> {
  late Customer _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = widget.customer;
  }

  void _upd(Customer c) => setState(() => _c = c);

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Container(
      decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(children: [
        SheetHandle(
          title: _c.id == 0 ? t.newCust : t.customers,
          trailing: TextButton(
              onPressed: widget.onCancel, child: const Text('← Back')),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: Column(children: [
              FieldInput(
                  label: t.custName,
                  value: _c.name,
                  onChanged: (v) => _upd(_c.copyWith(name: v))),
              Row(children: [
                Expanded(
                    child: FieldInput(
                        label: t.custReg,
                        value: _c.regNo,
                        onChanged: (v) => _upd(_c.copyWith(regNo: v)))),
                const SizedBox(width: 10),
                Expanded(
                    child: FieldInput(
                        label: t.custSST,
                        value: _c.sstRegNo,
                        onChanged: (v) => _upd(_c.copyWith(sstRegNo: v)))),
              ]),
              FieldInput(
                  label: t.custAddr,
                  value: _c.address,
                  multiline: true,
                  onChanged: (v) => _upd(_c.copyWith(address: v))),
              Row(children: [
                Expanded(
                    child: FieldInput(
                        label: t.custPhone,
                        value: _c.phone,
                        keyboard: TextInputType.phone,
                        onChanged: (v) => _upd(_c.copyWith(phone: v)))),
                const SizedBox(width: 10),
                Expanded(
                    child: FieldInput(
                        label: t.custEmail,
                        value: _c.email,
                        keyboard: TextInputType.emailAddress,
                        onChanged: (v) => _upd(_c.copyWith(email: v)))),
              ]),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _c.name.isEmpty || _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          await widget.onSave(_c);
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                      elevation: 0),
                  child: Text(_saving ? 'Saving…' : t.save,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CustCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback? onSelect, onEdit;
  final VoidCallback onDelete;
  const _CustCard(
      {required this.customer,
      this.onSelect,
      this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
    child: Row(children: [
      Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(customer.name,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
        if (customer.regNo.isNotEmpty)
          Text('Reg: ${customer.regNo}',
              style: const TextStyle(fontSize: 11, color: kMuted)),
        if (customer.phone.isNotEmpty)
          Text(customer.phone,
              style: const TextStyle(fontSize: 11, color: kMuted)),
      ])),
      if (onSelect != null) ...[
        SmBtn(
            label: 'Select',
            color: kDark,
            textColor: Colors.white,
            onTap: onSelect!),
        const SizedBox(width: 6),
      ],
      SmBtn(label: 'Edit', onTap: onEdit ?? () {}),
      const SizedBox(width: 6),
      GestureDetector(
          onTap: onDelete,
          child: const Icon(Icons.delete_outline, color: kRed, size: 22)),
    ]),
  );
}

// ─── Full Invoice Sheet ───────────────────────────────────────────────────────
class FullInvoiceSheet extends StatefulWidget {
  const FullInvoiceSheet({super.key});

  @override
  State<FullInvoiceSheet> createState() => _FullInvoiceSheetState();
}

class _FullInvoiceSheetState extends State<FullInvoiceSheet> {
  String _invNo   = '';
  String _invDate = nowISO();
  String _dueDate = '';
  String _notes = 'Payment due within 30 days.\nBank transfer preferred.';
  String _terms =
      '1. All prices in MYR.\n2. Goods sold are not returnable.\n3. Computer-generated invoice.';
  String _bankName = '';
  String _bankAcct = '';

  Customer _customer = Customer(id: 0, name: '');
  String? _logoB64;
  String? _sigB64;
  bool _showSigPad = false;
  bool _sharing = false;
  bool _saving = false;     // ← NEW: save state

  // ── New fields ─────────────────────────────────────────────────────────────
  String _shipToName  = '';
  String _shipToAddr  = '';
  String _payMethod   = 'Bank Transfer';
  String _payTerms    = 'Net 30 Days';
  String _latePenalty = '';
  String _bankAcctName = '';

  final List<Map<String, String>> _items = [
    {'desc': '', 'qty': '1', 'price': '', 'disc': '', 'sst': 'none', 'note': ''},
  ];

  final SignatureController _sigCtrl = SignatureController(
      penStrokeWidth: 2.5,
      penColor: kText,
      exportBackgroundColor: Colors.transparent);

  @override
  void dispose() {
    _sigCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Load sequential invoice number from DB
    DbService.nextInvoiceNo().then((no) {
      if (mounted) setState(() => _invNo = no);
    });
    // Auto-import company logo, signature, and bank from Settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = context.read<AppState>().settings;
      setState(() {
        if (_logoB64 == null && settings.logoBase64 != null)
          _logoB64 = settings.logoBase64;
        if (_sigB64 == null && settings.sigBase64 != null)
          _sigB64 = settings.sigBase64;
        if (_bankName.isEmpty && settings.bankName.isNotEmpty)
          _bankName = settings.bankName;
        if (_bankAcct.isEmpty && settings.bankAcct.isNotEmpty)
          _bankAcct = settings.bankAcct;
      });
    });
  }

  // ── Save invoice to DB ────────────────────────────────────────────────────
  Future<void> _saveInvoice() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final app = context.read<AppState>();
      await app.saveInvoice(
        invNo:    _invNo,
        invDate:  _invDate,
        dueDate:  _dueDate,
        customer: _customer,
        items:    _items,
        notes:    _notes,
        terms:    _terms,
        bankName: _bankName,
        bankAcct: _bankAcct,
        logoB64:  _logoB64,
        sigB64:   _sigB64,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Text('✅ ', style: TextStyle(fontSize: 16)),
              Text('Invoice $_invNo saved'),
            ]),
            backgroundColor: kDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Export as PDF and share ───────────────────────────────────────────────
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);

    final app = context.read<AppState>();

    try {
      final pdfBytes = await generateInvoicePdf(
        co:            app.settings,
        customer:      _customer,
        rows:          _items,
        invNo:         _invNo,
        invDate:       _invDate,
        dueDate:       _dueDate.isNotEmpty ? _dueDate : null,
        logoBase64:    _logoB64,
        sigBase64:     _sigB64,
        notes:         _notes.isNotEmpty   ? _notes   : null,
        terms:         _terms.isNotEmpty   ? _terms   : null,
        bankName:      _bankName.isNotEmpty ? _bankName : null,
        bankAcct:      _bankAcct.isNotEmpty ? _bankAcct : null,
        shipToName:    _shipToName.isNotEmpty ? _shipToName : null,
        shipToAddr:    _shipToAddr.isNotEmpty ? _shipToAddr : null,
        paymentMethod: _payMethod.isNotEmpty ? _payMethod : null,
        paymentTerms:  _payTerms.isNotEmpty  ? _payTerms  : null,
        latePenalty:   _latePenalty.isNotEmpty ? _latePenalty : null,
      );

      final dir  = await getTemporaryDirectory();
      final safe = _invNo.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      final file = File('${dir.path}/Invoice_$safe.pdf');
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Invoice $_invNo',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _pickLogo() async {
    final img = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 400);
    if (img == null) return;
    final bytes = await img.readAsBytes();
    setState(() =>
        _logoB64 = 'data:image/png;base64,${base64Encode(bytes)}');
  }

  Future<void> _saveSig() async {
    final data = await _sigCtrl.toPngBytes();
    if (data == null) return;
    setState(() {
      _sigB64 = 'data:image/png;base64,${base64Encode(data)}';
      _showSigPad = false;
    });
  }

  Map<String, double> _calcItem(Map<String, String> r) {
    final qty = double.tryParse(r['qty'] ?? '1') ?? 1;
    final price = double.tryParse(r['price'] ?? '0') ?? 0;
    final disc = double.tryParse(r['disc'] ?? '0') ?? 0;
    final sub = qty * price;
    final dAmt = sub * (disc / 100);
    final net = sub - dAmt;
    final sst = net * (sstRates[r['sst'] ?? 'none']?.rate ?? 0);
    return {'sub': sub, 'disc': dAmt, 'net': net, 'sst': sst, 'total': net + sst};
  }

  double get _subtotal =>
      _items.fold(0, (s, r) => s + (_calcItem(r)['net'] ?? 0));
  double get _totalSST =>
      _items.fold(0, (s, r) => s + (_calcItem(r)['sst'] ?? 0));
  double get _grand => _subtotal + _totalSST;

  // ── Select customer and auto-fill fields ──────────────────────────────────
  void _onCustomerSelected(Customer c) {
    setState(() => _customer = c);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = L10n(app.settings.lang);

    return Container(
      decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      height: MediaQuery.of(context).size.height * 0.96,
      child: Column(children: [
        // Top bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorder))),
          child: Row(children: [
            const Text('🧾 ', style: TextStyle(fontSize: 20)),
            Text(t.invoice,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
            const Spacer(),
            // ── Save button ──────────────────────────────────────────
            SmBtn(
              label: _saving ? 'Saving…' : '💾 Save',
              color: kGreenBg,
              borderColor: kGreenBd,
              textColor: kGreen,
              onTap: _saving ? () {} : _saveInvoice,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('📤', style: TextStyle(fontSize: 16)),
              label: Text(_sharing ? 'Sharing…' : t.sharePrint),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kDark,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                  elevation: 0),
            ),
            const SizedBox(width: 8),
            GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                        color: kBg, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 18, color: kMuted))),
          ]),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              // ── Branding ──────────────────────────────────────────────
              _SectionBox(
                  title: 'Company Branding',
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      Row(children: [
                        GestureDetector(
                          onTap: _pickLogo,
                          child: Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                  color: kSurface,
                                  border: Border.all(color: kBorder, width: 1.5),
                                  borderRadius: BorderRadius.circular(10)),
                              child: _logoB64 != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.memory(
                                          base64Decode(
                                              _logoB64!.split(',').last),
                                          fit: BoxFit.contain))
                                  : const Center(
                                      child: Text('🏢',
                                          style: TextStyle(fontSize: 28)))),
                        ),
                        const SizedBox(width: 12),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(t.logo,
                              style: const TextStyle(fontSize: 11, color: kMuted)),
                          const SizedBox(height: 6),
                          Row(children: [
                            SmBtn(label: '📁 Upload', onTap: _pickLogo),
                            if (_logoB64 != null) ...[
                              const SizedBox(width: 6),
                              SmBtn(
                                  label: '✕',
                                  color: kRedBg,
                                  borderColor: kRedBd,
                                  textColor: kRed,
                                  onTap: () => setState(() => _logoB64 = null)),
                            ],
                          ]),
                        ]),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Container(
                            width: 70,
                            height: 44,
                            decoration: BoxDecoration(
                                color: kSurface,
                                border: Border.all(color: kBorder, width: 1.5),
                                borderRadius: BorderRadius.circular(8)),
                            child: _sigB64 != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.memory(
                                        base64Decode(_sigB64!.split(',').last),
                                        fit: BoxFit.contain))
                                : const Center(
                                    child: Text('✍️',
                                        style: TextStyle(fontSize: 22)))),
                        const SizedBox(width: 12),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(t.sig,
                              style: const TextStyle(fontSize: 11, color: kMuted)),
                          const SizedBox(height: 6),
                          SmBtn(
                              label: '✏️ ${t.drawSig}',
                              onTap: () => setState(
                                  () => _showSigPad = !_showSigPad)),
                        ]),
                      ]),
                      if (_showSigPad) ...[
                        const SizedBox(height: 12),
                        Container(
                            decoration: BoxDecoration(
                                color: const Color(0xFFFAFAF8),
                                border: Border.all(color: kBorder, width: 1.5),
                                borderRadius: BorderRadius.circular(12)),
                            child: Signature(
                                controller: _sigCtrl,
                                height: 140,
                                backgroundColor: Colors.transparent)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                                  onPressed: () {
                                    _sigCtrl.clear();
                                    setState(() {});
                                  },
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: kMuted,
                                      side: const BorderSide(color: kBorder)),
                                  child: Text(t.clearSig))),
                          const SizedBox(width: 10),
                          Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                  onPressed: _saveSig,
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: kDark,
                                      foregroundColor: Colors.white,
                                      elevation: 0),
                                  child: Text(t.saveSig))),
                        ]),
                      ],
                    ]),
                  )),
              const SizedBox(height: 12),

              // ── Invoice header ─────────────────────────────────────────
              Row(children: [
                Expanded(
                    child: _TextField(
                        label: t.invNo,
                        value: _invNo,
                        onChanged: (v) => setState(() => _invNo = v))),
                const SizedBox(width: 10),
                Expanded(
                    child: _DateField(
                        label: t.invDate,
                        value: _invDate,
                        onChanged: (v) => setState(() => _invDate = v))),
              ]),
              _DateField(
                  label: '${t.dueDate} (optional)',
                  value: _dueDate,
                  onChanged: (v) => setState(() => _dueDate = v)),
              const SizedBox(height: 4),

              // ── Customer ────────────────────────────────────────────────
              _SectionBox(
                title: t.billTo,
                headerAction: SmBtn(
                  label: '📋 ${t.customers}',
                  color: kBlue,
                  textColor: Colors.white,
                  // FIX: pass _onCustomerSelected so fields auto-fill after selection
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => CustomerManagerScreen(
                        onSelect: _onCustomerSelected),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(children: [
                    // FIX: use key: ValueKey(_customer.id) so fields rebuild when customer changes
                    FieldInput(
                        key: ValueKey('cust_name_${_customer.id}'),
                        label: t.custName,
                        value: _customer.name,
                        onChanged: (v) => setState(
                            () => _customer = _customer.copyWith(name: v))),
                    Row(children: [
                      Expanded(
                          child: FieldInput(
                              key: ValueKey('cust_reg_${_customer.id}'),
                              label: t.custReg,
                              value: _customer.regNo,
                              onChanged: (v) => setState(() =>
                                  _customer = _customer.copyWith(regNo: v)))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FieldInput(
                              key: ValueKey('cust_sst_${_customer.id}'),
                              label: t.custSST,
                              value: _customer.sstRegNo,
                              onChanged: (v) => setState(() =>
                                  _customer =
                                      _customer.copyWith(sstRegNo: v)))),
                    ]),
                    FieldInput(
                        key: ValueKey('cust_addr_${_customer.id}'),
                        label: t.custAddr,
                        value: _customer.address,
                        multiline: true,
                        onChanged: (v) => setState(
                            () => _customer = _customer.copyWith(address: v))),
                    Row(children: [
                      Expanded(
                          child: FieldInput(
                              key: ValueKey('cust_phone_${_customer.id}'),
                              label: t.custPhone,
                              value: _customer.phone,
                              keyboard: TextInputType.phone,
                              onChanged: (v) => setState(() =>
                                  _customer = _customer.copyWith(phone: v)))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FieldInput(
                              key: ValueKey('cust_email_${_customer.id}'),
                              label: t.custEmail,
                              value: _customer.email,
                              keyboard: TextInputType.emailAddress,
                              onChanged: (v) => setState(() =>
                                  _customer = _customer.copyWith(email: v)))),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ── Items ──────────────────────────────────────────────────
              const _SectionLabel2(label: 'Items'),
              ..._items.asMap().entries.map((e) {
                final i = e.key;
                final r = e.value;
                return _ItemCard(
                  row: r,
                  index: i,
                  calc: _calcItem(r),
                  canDelete: _items.length > 1,
                  onChanged: (k, v) => setState(() => _items[i][k] = v),
                  onDelete: () => setState(() => _items.removeAt(i)),
                );
              }),
              DashedBtn(
                  label: '+ Add Item',
                  onTap: () => setState(() => _items.add({
                        'desc': '',
                        'qty': '1',
                        'price': '',
                        'disc': '',
                        'sst': 'none',
                        'note': ''
                      }))),
              const SizedBox(height: 14),

              // ── Totals ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: kSurface,
                    border: Border.all(color: kBorder),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  _TotalRow(label: t.subTotal, value: _subtotal),
                  _TotalRow(label: 'SST', value: _totalSST),
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: kBorder, width: 2))),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(t.grandTotal,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w900)),
                          Text(fmtMYR(_grand),
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: kText)),
                        ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // ── Bank ───────────────────────────────────────────────────
              Row(children: [
                Expanded(
                    child: _TextField(
                        label: t.bankName,
                        value: _bankName,
                        onChanged: (v) => setState(() => _bankName = v))),
                const SizedBox(width: 10),
                Expanded(
                    child: _TextField(
                        label: t.bankAcct,
                        value: _bankAcct,
                        keyboard: TextInputType.number,
                        onChanged: (v) => setState(() => _bankAcct = v))),
              ]),
              _TextField(
                  label: 'Account Name',
                  value: _bankAcctName,
                  onChanged: (v) => setState(() => _bankAcctName = v)),

              // ── Ship To ────────────────────────────────────────────────
              const _SectionLabel2(label: 'Ship To'),
              _TextField(
                  label: 'Recipient Name (leave blank = same as Bill To)',
                  value: _shipToName,
                  onChanged: (v) => setState(() => _shipToName = v)),
              _TextAreaField(
                  label: 'Shipping Address',
                  value: _shipToAddr,
                  onChanged: (v) => setState(() => _shipToAddr = v)),

              // ── Payment Terms ──────────────────────────────────────────
              const _SectionLabel2(label: 'Payment Terms'),
              Row(children: [
                Expanded(
                    child: _TextField(
                        label: 'Payment Method',
                        value: _payMethod,
                        onChanged: (v) => setState(() => _payMethod = v))),
                const SizedBox(width: 10),
                Expanded(
                    child: _TextField(
                        label: 'Terms (e.g. Net 30)',
                        value: _payTerms,
                        onChanged: (v) => setState(() => _payTerms = v))),
              ]),
              _TextField(
                  label: 'Late Payment Penalty (e.g. 1.5% per month)',
                  value: _latePenalty,
                  onChanged: (v) => setState(() => _latePenalty = v)),
              _TextAreaField(
                  label: t.notes,
                  value: _notes,
                  onChanged: (v) => setState(() => _notes = v)),
              _TextAreaField(
                  label: t.terms,
                  value: _terms,
                  onChanged: (v) => setState(() => _terms = v)),
              const SizedBox(height: 8),

              // ── Bottom action buttons ──────────────────────────────────
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _saveInvoice,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('💾', style: TextStyle(fontSize: 16)),
                    label: Text(_saving ? 'Saving…' : t.save),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kGreen,
                        side: const BorderSide(color: kGreenBd),
                        backgroundColor: kGreenBg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('📤', style: TextStyle(fontSize: 20)),
                    label: Text(_sharing ? 'Sharing…' : t.sharePrint),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: kDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Item card ────────────────────────────────────────────────────────────────
class _ItemCard extends StatelessWidget {
  final Map<String, String> row;
  final int index;
  final Map<String, double> calc;
  final bool canDelete;
  final void Function(String k, String v) onChanged;
  final VoidCallback onDelete;

  const _ItemCard(
      {required this.row,
      required this.index,
      required this.calc,
      required this.canDelete,
      required this.onChanged,
      required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: kBg,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: _InlineField(
                value: row['desc'] ?? '',
                placeholder: 'Item description',
                onChanged: (v) => onChanged('desc', v))),
        if (canDelete) ...[
          const SizedBox(width: 8),
          GestureDetector(
              onTap: onDelete,
              child: const Icon(Icons.close, color: kRed, size: 20)),
        ],
      ]),
      const SizedBox(height: 8),
      _InlineField(
          value: row['note'] ?? '',
          placeholder: 'Note (optional)',
          onChanged: (v) => onChanged('note', v),
          style: const TextStyle(fontSize: 11, color: kMuted)),
      const SizedBox(height: 8),
      Row(children: [
        _MiniField(
            label: 'Qty',
            width: 60,
            value: row['qty'] ?? '1',
            keyboard: TextInputType.number,
            onChanged: (v) => onChanged('qty', v)),
        const SizedBox(width: 8),
        Expanded(
            child: _MiniField(
                label: 'Unit Price',
                value: row['price'] ?? '',
                keyboard: TextInputType.number,
                onChanged: (v) => onChanged('price', v))),
        const SizedBox(width: 8),
        _MiniField(
            label: 'Disc %',
            width: 70,
            value: row['disc'] ?? '',
            keyboard: TextInputType.number,
            onChanged: (v) => onChanged('disc', v)),
        const SizedBox(width: 8),
        _SSTDrop(
            value: row['sst'] ?? 'none',
            onChanged: (v) => onChanged('sst', v)),
      ]),
      const SizedBox(height: 6),
      Align(
          alignment: Alignment.centerRight,
          child: Text(
            (calc['sst'] ?? 0) > 0
                ? 'Net ${fmtMYR(calc['net'] ?? 0)} + SST ${fmtMYR(calc['sst'] ?? 0)} = ${fmtMYR(calc['total'] ?? 0)}'
                : fmtMYR(calc['total'] ?? 0),
            style: const TextStyle(fontSize: 12, color: kMuted),
          )),
    ]),
  );
}

class _InlineField extends StatelessWidget {
  final String value, placeholder;
  final ValueChanged<String> onChanged;
  final TextStyle? style;

  const _InlineField(
      {required this.value,
      required this.placeholder,
      required this.onChanged,
      this.style});

  @override
  Widget build(BuildContext context) => TextField(
    controller: TextEditingController(text: value)
      ..selection = TextSelection.collapsed(offset: value.length),
    onChanged: onChanged,
    decoration: InputDecoration(
        hintText: placeholder,
        filled: true,
        fillColor: kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: kBorder))),
    style: style ?? const TextStyle(fontSize: 13, color: kText),
  );
}

class _MiniField extends StatelessWidget {
  final String label, value;
  final double? width;
  final TextInputType? keyboard;
  final ValueChanged<String> onChanged;

  const _MiniField(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.width,
      this.keyboard});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      TextField(
        controller: TextEditingController(text: value)
          ..selection = TextSelection.collapsed(offset: value.length),
        onChanged: onChanged,
        keyboardType: keyboard,
        decoration: InputDecoration(
            filled: true,
            fillColor: kSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kBorder))),
        style: const TextStyle(fontSize: 12, color: kText),
      ),
    ]),
  );
}

class _SSTDrop extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SSTDrop({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('SST',
            style: TextStyle(
                fontSize: 9, color: kMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              color: kSurface,
              border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              items: sstRates.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                          e.value.enLabel
                              .replaceAll(' Tax', '')
                              .replaceAll('Service ', 'Svc '),
                          style: const TextStyle(fontSize: 10))))
                  .toList(),
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ),
      ]);
}

// ─── Section helpers ──────────────────────────────────────────────────────────
class _SectionBox extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? headerAction;

  const _SectionBox(
      {required this.title, required this.child, this.headerAction});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        decoration: const BoxDecoration(
            color: kBlueBg,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(14)),
            border: Border(bottom: BorderSide(color: kBlueBd))),
        child: Row(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: kBlue)),
          const Spacer(),
          if (headerAction != null) headerAction!,
        ]),
      ),
      child,
    ]),
  );
}

class _SectionLabel2 extends StatelessWidget {
  final String label;
  const _SectionLabel2({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kMuted,
            letterSpacing: 0.5)),
  );
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double value;
  const _TotalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: kMuted)),
      Text(fmtMYR(value), style: const TextStyle(fontSize: 13, color: kText)),
    ]),
  );
}

class _TextField extends StatelessWidget {
  final String label, value;
  final TextInputType? keyboard;
  final ValueChanged<String> onChanged;

  const _TextField(
      {required this.label,
      required this.value,
      required this.onChanged,
      this.keyboard});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kMuted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          keyboardType: keyboard,
          decoration: InputDecoration(
              filled: true,
              fillColor: kBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide:
                      const BorderSide(color: kBorder, width: 1.5)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide:
                      const BorderSide(color: kBorder, width: 1.5))),
          style: const TextStyle(fontSize: 14, color: kText),
        ),
        const SizedBox(height: 10),
      ]);
}

class _TextAreaField extends StatelessWidget {
  final String label, value;
  final ValueChanged<String> onChanged;

  const _TextAreaField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kMuted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          maxLines: 3,
          decoration: InputDecoration(
              filled: true,
              fillColor: kBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide:
                      const BorderSide(color: kBorder, width: 1.5)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide:
                      const BorderSide(color: kBorder, width: 1.5))),
          style: const TextStyle(fontSize: 13, color: kText),
        ),
        const SizedBox(height: 10),
      ]);
}

class _DateField extends StatelessWidget {
  final String label, value;
  final ValueChanged<String> onChanged;

  const _DateField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: kMuted,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () async {
            DateTime initial;
            try {
              initial = DateTime.parse(value);
            } catch (_) {
              initial = DateTime.now();
            }
            final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030));
            if (picked != null) {
              onChanged(picked.toIso8601String().substring(0, 10));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
                color: kBg,
                border: Border.all(color: kBorder, width: 1.5),
                borderRadius: BorderRadius.circular(11)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(value.isNotEmpty ? value : '—',
                      style: const TextStyle(fontSize: 14, color: kText)),
                  const Icon(Icons.calendar_today, size: 15, color: kMuted),
                ]),
          ),
        ),
        const SizedBox(height: 10),
      ]);
}
