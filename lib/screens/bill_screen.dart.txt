import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/accounting_state.dart';
import '../accounting_models.dart';
import '../utils.dart';

// ════════════════════════════════════════════════════════════════════════════
// BILL SCREEN
// ════════════════════════════════════════════════════════════════════════════

class _BillType {
  final String id, icon, enLabel, zhLabel;
  const _BillType(this.id, this.icon, this.enLabel, this.zhLabel);
  String label(String lang) => lang == 'zh' ? zhLabel : enLabel;
}

const _billTypes = [
  _BillType('rent',  '🏢', 'Rental / Utilities',   '租金/水电'),
  _BillType('mkt',   '📣', 'Marketing / Ads',       '广告/营销'),
  _BillType('inv',   '📦', 'Inventory / Purchases', '进货/采购'),
  _BillType('util',  '⚡', 'Utilities',             '水电费'),
  _BillType('prof',  '⚖️', 'Professional Fees',     '专业服务费'),
  _BillType('rep',   '🔧', 'Repairs / Maintenance', '维修维护'),
  _BillType('ins',   '🛡️', 'Insurance',             '保险'),
  _BillType('other', '💸', 'Other Expense',         '其他支出'),
];

enum _PayStatus { unpaid, cash, bank }

extension _PayStatusExt on _PayStatus {
  String label(String lang) => switch (this) {
    _PayStatus.unpaid => lang == 'zh' ? '未付款'       : 'Unpaid',
    _PayStatus.cash   => lang == 'zh' ? '已付（现金）' : 'Paid (Cash)',
    _PayStatus.bank   => lang == 'zh' ? '已付（银行）' : 'Paid (Bank)',
  };
  String get icon => switch (this) {
    _PayStatus.unpaid => '⏳',
    _PayStatus.cash   => '💵',
    _PayStatus.bank   => '🏦',
  };
  String get suffix => switch (this) {
    _PayStatus.unpaid => 'unpaid',
    _PayStatus.cash   => 'cash',
    _PayStatus.bank   => 'bank',
  };
}

class BillFormSheet extends StatefulWidget {
  const BillFormSheet({super.key});
  @override State<BillFormSheet> createState() => _BillFormSheetState();
}

class _BillFormSheetState extends State<BillFormSheet> {
  final _supplierCtrl = TextEditingController();
  final _amtCtrl      = TextEditingController();
  final _notesCtrl    = TextEditingController();
  String     _billNo    = '';
  String     _date      = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String     _dueDate   = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
  _BillType  _type      = _billTypes[0];
  _PayStatus _payStatus = _PayStatus.unpaid;
  bool       _saving    = false;
  String?    _error;

  @override
  void initState() {
    super.initState();
    _billNo = 'BILL-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _amtCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String get _catId => 'bill_${_type.id}_${_payStatus.suffix}';

  Future<void> _save() async {
    final supplier = _supplierCtrl.text.trim();
    final amt      = double.tryParse(_amtCtrl.text) ?? 0;
    if (supplier.isEmpty) { setState(() => _error = 'Supplier name is required'); return; }
    if (amt <= 0)         { setState(() => _error = 'Amount must be greater than 0'); return; }

    setState(() { _saving = true; _error = null; });
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final app = context.read<AppState>();
      final cat = findCat(_catId);
      if (cat == null) throw Exception('Category not found: $_catId');

      // 1. Write Transaction → syncs to Reports + GL
      await app.addOrUpdateTx(Transaction(
        id:           DateTime.now().millisecondsSinceEpoch,
        type:         'expense',
        catId:        _catId,
        amountMYR:    amt,
        origAmount:   amt,
        origCurrency: 'MYR',
        sstKey:       'none',
        sstMYR:       0,
        descEN:       '$supplier – ${_type.enLabel}',
        descZH:       '$supplier – ${_type.zhLabel}',
        date:         _date,
        entries:      cat.mkEntries(amt),
      ));

      // 2. Write ApBill → syncs to Accounting → Payable
      try {
        final acc = context.read<AccountingState>();
        await acc.saveApBill(ApBill(
          id:           DateTime.now().millisecondsSinceEpoch,
          billNo:       _billNo,
          supplierId:   supplier,
          supplierName: supplier,
          issueDate:    _date,
          dueDate:      _payStatus == _PayStatus.unpaid ? _dueDate : _date,
          subtotal:     amt,
          sstAmount:    0,
          total:        amt,
          amountPaid:   _payStatus != _PayStatus.unpaid ? amt : 0,
          status:       _payStatus != _PayStatus.unpaid
                          ? InvoiceStatus.paid
                          : InvoiceStatus.sent,
          notes:        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          category:     _type.enLabel,
        ));
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text('Bill $_billNo saved'),
          ]),
          backgroundColor: kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final fmt  = NumberFormat('#,##0.00');

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.93),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 10),
            Row(children: [
              Text(lang == 'zh' ? '📄 添加账单' : '📄 Add Bill',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context),
                child: const Text('✕', style: TextStyle(color: kMuted, fontSize: 16))),
            ]),
          ]),
        ),

        Expanded(child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Bill No + Date
            Row(children: [
              Expanded(child: _field(lang == 'zh' ? '账单号' : 'Bill No.', TextField(
                controller: TextEditingController(text: _billNo),
                onChanged: (v) => _billNo = v,
                style: const TextStyle(fontSize: 14, color: kText),
                decoration: _dec('BILL-001'),
              ))),
              const SizedBox(width: 12),
              Expanded(child: _field(lang == 'zh' ? '日期' : 'Date',
                _datebtn(_date, (d) => setState(() => _date = d), context))),
            ]),

            // Supplier
            _field(lang == 'zh' ? '供应商名称 *' : 'Supplier Name *', TextField(
              controller: _supplierCtrl,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec(lang == 'zh' ? '供应商名称' : 'Supplier name'),
            )),

            // Amount
            _field(lang == 'zh' ? '金额 (MYR) *' : 'Amount (MYR) *', TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec('0.00', prefix: 'RM '),
            )),

            // Expense Type
            _field(lang == 'zh' ? '费用类型 *' : 'Expense Type *',
              Wrap(spacing: 8, runSpacing: 8, children: _billTypes.map((bt) {
                final sel = _type.id == bt.id;
                return GestureDetector(
                  onTap: () => setState(() => _type = bt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:  sel ? kDark : kSurface,
                      border: Border.all(color: sel ? kDark : kBorder, width: 1.5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('${bt.icon} ${bt.label(lang)}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : kMuted)),
                  ),
                );
              }).toList()),
            ),

            // Payment Status
            _field(lang == 'zh' ? '付款状态 *' : 'Payment Status *',
              Row(children: [
                for (int i = 0; i < _PayStatus.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _payStatus = _PayStatus.values[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color:  _payStatus == _PayStatus.values[i]
                                  ? _payColor(_PayStatus.values[i]) : kSurface,
                        border: Border.all(
                          color: _payStatus == _PayStatus.values[i]
                                  ? _payColor(_PayStatus.values[i]) : kBorder,
                          width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(children: [
                        Text(_PayStatus.values[i].icon, style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 3),
                        Text(_PayStatus.values[i].label(lang),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: _payStatus == _PayStatus.values[i] ? Colors.white : kMuted)),
                      ]),
                    ),
                  )),
                ],
              ]),
            ),

            // Due Date (unpaid only)
            if (_payStatus == _PayStatus.unpaid)
              _field(lang == 'zh' ? '到期日' : 'Due Date',
                _datebtn(_dueDate, (d) => setState(() => _dueDate = d), context)),

            // Notes
            _field(lang == 'zh' ? '备注（可选）' : 'Notes (optional)', TextField(
              controller: _notesCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: kText),
              decoration: _dec(lang == 'zh' ? '可选备注' : 'Optional notes'),
            )),

            // GL Preview
            const SizedBox(height: 4),
            _buildGlPreview(fmt),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kRedBd)),
                child: Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
              ),
            ],

            // Save Button
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kDark, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(lang == 'zh' ? '保存账单' : 'Save Bill',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              )),
          ]),
        )),
      ]),
    );
  }

  Widget _buildGlPreview(NumberFormat fmt) {
    final cat = findCat(_catId);
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    if (cat == null || amt <= 0) return const SizedBox.shrink();
    final entries = cat.mkEntries(amt);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCDD7FF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('📒', style: TextStyle(fontSize: 13)),
          SizedBox(width: 6),
          Text('Journal Entry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3344AA))),
        ]),
        const SizedBox(height: 8),
        ...entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(width: 28, child: Text(e.dc, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3344AA), fontFamily: 'monospace'))),
            Expanded(child: Text(accounts[e.acc]?.name ?? e.acc, style: const TextStyle(fontSize: 11, color: Color(0xFF3344AA)))),
            Text('RM ${fmt.format(e.val)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3344AA))),
          ]),
        )),
      ]),
    );
  }

  Color _payColor(_PayStatus ps) => switch (ps) {
    _PayStatus.unpaid => const Color(0xFFD97706),
    _PayStatus.cash   => kGreen,
    _PayStatus.bank   => kBlue,
  };

  Widget _field(String label, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      child,
    ]),
  );

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
    hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 13),
    prefixText: prefix, prefixStyle: const TextStyle(color: kText, fontWeight: FontWeight.w600),
    filled: true, fillColor: kBg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDark, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _datebtn(String val, ValueChanged<String> onChange, BuildContext ctx) =>
    GestureDetector(
      onTap: () async {
        final d = await showDatePicker(
          context: ctx,
          initialDate: DateTime.tryParse(val) ?? DateTime.now(),
          firstDate: DateTime(2020), lastDate: DateTime(2035),
        );
        if (d != null) onChange(DateFormat('yyyy-MM-dd').format(d));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 15, color: kMuted),
          const SizedBox(width: 8),
          Text(val, style: const TextStyle(fontSize: 13, color: kText)),
        ]),
      ),
    );
}

// ════════════════════════════════════════════════════════════════════════════
// AP BILL PAYMENT SHEET
// Shown from Accounting → Payable list when tapping an unpaid/partial bill.
// Lets the user record a payment as Cash or Bank Transfer.
// ════════════════════════════════════════════════════════════════════════════
class ApBillPaymentSheet extends StatefulWidget {
  final ApBill bill;
  const ApBillPaymentSheet({super.key, required this.bill});

  @override
  State<ApBillPaymentSheet> createState() => _ApBillPaymentSheetState();
}

class _ApBillPaymentSheetState extends State<ApBillPaymentSheet> {
  late TextEditingController _amtCtrl;
  _PayStatus _method = _PayStatus.cash; // cash or bank only (not unpaid)
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Default to remaining balance
    _amtCtrl = TextEditingController(
      text: widget.bill.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    if (amt <= 0) return;
    setState(() => _saving = true);
    try {
      final acc = context.read<AccountingState>();
      await acc.recordApPayment(widget.bill.id, amt);
      if (mounted) {
        final lang = context.read<AppState>().settings.lang;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text(lang == 'zh'
              ? '已付款 RM ${amt.toStringAsFixed(2)}'
              : 'Payment recorded: RM ${amt.toStringAsFixed(2)}'),
          ]),
          backgroundColor: kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.of(context).pop(true); // return true = updated
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final bill = widget.bill;

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 0,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        const SizedBox(height: 12),
        Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99)))),
        const SizedBox(height: 16),

        // Title
        Row(children: [
          const Text('💳', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '记录付款' : 'Record Payment',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              Text('${bill.billNo} · ${bill.supplierName}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            ]),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: kMuted)),
          ),
        ]),
        const SizedBox(height: 20),

        // Balance summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '账单总额' : 'Bill Total',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${bill.total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '已付' : 'Paid',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${bill.amountPaid.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kGreen)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '余额' : 'Balance',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${bill.balance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kRed)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Amount field
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((lang == 'zh' ? '付款金额 (MYR)' : 'Payment Amount (MYR)').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
            decoration: InputDecoration(
              prefixText: 'RM ',
              prefixStyle: const TextStyle(color: kText, fontWeight: FontWeight.w600),
              filled: true, fillColor: kBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDark, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // Payment method: Cash or Bank only
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((lang == 'zh' ? '付款方式' : 'Payment Method').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(children: [
            for (final ps in [_PayStatus.cash, _PayStatus.bank]) ...[
              if (ps == _PayStatus.bank) const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _method = ps),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color:  _method == ps ? _payColor(ps) : kSurface,
                    border: Border.all(color: _method == ps ? _payColor(ps) : kBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text(ps.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(ps.label(lang),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: _method == ps ? Colors.white : kMuted)),
                  ]),
                ),
              )),
            ],
          ]),
        ]),
        const SizedBox(height: 20),

        // Confirm button
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _pay,
            icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('✅', style: TextStyle(fontSize: 18)),
            label: Text(_saving
              ? (lang == 'zh' ? '处理中…' : 'Processing…')
              : (lang == 'zh' ? '确认付款' : 'Confirm Payment'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Color _payColor(_PayStatus ps) => switch (ps) {
    _PayStatus.cash => kGreen,
    _PayStatus.bank => kBlue,
    _         => const Color(0xFFD97706),
  };
}

// ════════════════════════════════════════════════════════════════════════════
// AR INVOICE PAYMENT SHEET  
// Same concept for AR invoices (收款).
// ════════════════════════════════════════════════════════════════════════════
class ArInvoicePaymentSheet extends StatefulWidget {
  final ArInvoice invoice;
  const ArInvoicePaymentSheet({super.key, required this.invoice});

  @override
  State<ArInvoicePaymentSheet> createState() => _ArInvoicePaymentSheetState();
}

class _ArInvoicePaymentSheetState extends State<ArInvoicePaymentSheet> {
  late TextEditingController _amtCtrl;
  _PayStatus _method = _PayStatus.bank;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amtCtrl = TextEditingController(
      text: widget.invoice.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _collect() async {
    final amt = double.tryParse(_amtCtrl.text) ?? 0;
    if (amt <= 0) return;
    setState(() => _saving = true);
    try {
      final acc = context.read<AccountingState>();
      await acc.recordArPayment(widget.invoice.id, amt);
      if (mounted) {
        final lang = context.read<AppState>().settings.lang;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Text('✅ ', style: TextStyle(fontSize: 16)),
            Text(lang == 'zh'
              ? '已收款 RM ${amt.toStringAsFixed(2)}'
              : 'Payment received: RM ${amt.toStringAsFixed(2)}'),
          ]),
          backgroundColor: kDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<AppState>().settings.lang;
    final inv  = widget.invoice;

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 20, right: 20, top: 0,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Center(child: Container(width: 40, height: 4,
          decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99)))),
        const SizedBox(height: 16),

        Row(children: [
          const Text('💰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '记录收款' : 'Record Payment Received',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              Text('${inv.invNo} · ${inv.customerName}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            ]),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: kMuted)),
          ),
        ]),
        const SizedBox(height: 20),

        // Balance summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '发票总额' : 'Invoice Total',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${inv.total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '已收' : 'Received',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${inv.amountPaid.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kGreen)),
            ])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lang == 'zh' ? '余额' : 'Outstanding',
                style: const TextStyle(fontSize: 11, color: kMuted)),
              Text('RM ${inv.balance.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kRed)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Amount
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((lang == 'zh' ? '收款金额 (MYR)' : 'Amount Received (MYR)').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _amtCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
            decoration: InputDecoration(
              prefixText: 'RM ',
              prefixStyle: const TextStyle(color: kText, fontWeight: FontWeight.w600),
              filled: true, fillColor: kBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kDark, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // Method
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((lang == 'zh' ? '收款方式' : 'Payment Method').toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Row(children: [
            for (final ps in [_PayStatus.cash, _PayStatus.bank]) ...[
              if (ps == _PayStatus.bank) const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => setState(() => _method = ps),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color:  _method == ps ? _payColor(ps) : kSurface,
                    border: Border.all(color: _method == ps ? _payColor(ps) : kBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    Text(ps.icon, style: const TextStyle(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(ps.label(lang),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: _method == ps ? Colors.white : kMuted)),
                  ]),
                ),
              )),
            ],
          ]),
        ]),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _collect,
            icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('💰', style: TextStyle(fontSize: 18)),
            label: Text(_saving
              ? (lang == 'zh' ? '处理中…' : 'Processing…')
              : (lang == 'zh' ? '确认收款' : 'Confirm Receipt'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  Color _payColor(_PayStatus ps) => switch (ps) {
    _PayStatus.cash => kGreen,
    _PayStatus.bank => kBlue,
    _         => const Color(0xFFD97706),
  };
}
