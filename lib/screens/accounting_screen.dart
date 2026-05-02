import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/accounting_state.dart';
import '../accounting_models.dart';

// ── Account type from code prefix ────────────────────────────────────────────
String _accType(String code) {
  final prefix = code.isNotEmpty ? code[0] : '9';
  switch (prefix) {
    case '1': return 'Asset';
    case '2': return 'Liability';
    case '3': return 'Equity';
    case '4': return 'Revenue';
    case '5': return 'Expense';
    default:  return 'Other';
  }
}


// ════════════════════════════════════════════════════════════════════════════
// ACCOUNTING SCREEN — tabs: AR | AP | Trial Balance | GL
// ════════════════════════════════════════════════════════════════════════════
class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});
  @override State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final acc = context.read<AccountingState>();
      // Inject AppState so payments auto-sync to GL
      acc.appState = context.read<AppState>();
      acc.init();
    });
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = L10n(context.read<AppState>().settings.lang);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('📚  ${t.accounting}'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: kText,
          unselectedLabelColor: kMuted,
          indicatorColor: kDark,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs:[
            Tab(text: t.receivable),
            Tab(text: t.payable),
            Tab(text: t.trialBalance),
            Tab(text: t.generalLedger),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ArTab(),
          _ApTab(),
          _TrialBalanceTab(),
          _GeneralLedgerTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 1 — ACCOUNTS RECEIVABLE
// ════════════════════════════════════════════════════════════════════════════
class _ArTab extends StatefulWidget {
  const _ArTab();
  @override State<_ArTab> createState() => _ArTabState();
}

class _ArTabState extends State<_ArTab> {
  InvoiceStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final acc = context.watch<AccountingState>();
    final fmt = NumberFormat('#,##0.00');
    final t = L10n(context.read<AppState>().settings.lang);
    final aging = acc.arAgingSummary;
    final list  = acc.arByStatus(_filter);

    return Column(children: [
      // ── Summary strip ───────────────────────────────────────────────────
      Container(
        color: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _SummaryChip(label: t.totalAr,  value: 'RM ${fmt.format(acc.totalReceivable)}', color: kGreen),
          _SummaryChip(label: t.overdue,   value: 'RM ${fmt.format(acc.totalOverdueAr)}',  color: kRed),
          _SummaryChip(label: t.invoice,  value: '${acc.arInvoices.length}',              color: kText),
        ]),
      ),

      // ── Aging bar ───────────────────────────────────────────────────────
      if (aging.total > 0)
        _AgingBar(aging: aging),

      // ── Filter chips ────────────────────────────────────────────────────
      _FilterRow(
        selected: _filter,
        onSelect: (s) => setState(() => _filter = s),
      ),

      // ── List ────────────────────────────────────────────────────────────
      Expanded(child: list.isEmpty
        ? _EmptyState(label: t.noTx, onAdd: () => _showArForm(context))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ArInvoiceCard(
              invoice: list[i],
              onTap: () => _showArDetail(context, list[i]),
            ),
          ),
      ),
    ]);
  }

  void _showArForm(BuildContext context, {ArInvoice? inv}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccountingState>(),
        child: _ArInvoiceForm(invoice: inv),
      ),
    );
  }

  void _showArDetail(BuildContext context, ArInvoice inv) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccountingState>(),
        child: _ArDetailSheet(invoice: inv, onEdit: () {
          Navigator.pop(context);
          _showArForm(context, inv: inv);
        }),
      ),
    );
  }

}

// ── AR Invoice Card ───────────────────────────────────────────────────────────
class _ArInvoiceCard extends StatelessWidget {
  final ArInvoice invoice;
  final VoidCallback onTap;
  const _ArInvoiceCard({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final s   = invoice.status;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: s == InvoiceStatus.overdue ? kRedBd : kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(invoice.invNo,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText))),
            _StatusBadge(status: s),
          ]),
          const SizedBox(height: 4),
          Text(invoice.customerName, style: const TextStyle(fontSize: 13, color: kMuted)),
          const SizedBox(height: 8),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total', style: TextStyle(fontSize: 10, color: kMuted)),
              Text('RM ${fmt.format(invoice.total)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
            ]),
            const SizedBox(width: 24),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Balance', style: TextStyle(fontSize: 10, color: kMuted)),
              Text('RM ${fmt.format(invoice.balance)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                  color: invoice.balance > 0 ? kRed : kGreen)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Due', style: TextStyle(fontSize: 10, color: kMuted)),
              Text(invoice.dueDate,
                style: TextStyle(fontSize: 12, color: invoice.isOverdue ? kRed : kMuted)),
            ]),
          ]),
          if (invoice.isOverdue) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(99)),
              child: Text('${invoice.daysOverdue} days overdue',
                style: const TextStyle(fontSize: 11, color: kRed, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── AR Detail Sheet ───────────────────────────────────────────────────────────
class _ArDetailSheet extends StatefulWidget {
  final ArInvoice invoice;
  final VoidCallback onEdit;
  const _ArDetailSheet({required this.invoice, required this.onEdit});
  @override State<_ArDetailSheet> createState() => _ArDetailSheetState();
}

class _ArDetailSheetState extends State<_ArDetailSheet> {
  final _payCtrl = TextEditingController();
  bool _paying = false;

  Future<void> _recordPayment() async {
    final amt = double.tryParse(_payCtrl.text) ?? 0;
    if (amt <= 0) return;
    setState(() => _paying = true);
    await context.read<AccountingState>().recordArPayment(widget.invoice.id, amt);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final t   = L10n(context.read<AppState>().settings.lang);
    final inv = widget.invoice;

    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(inv.invNo,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kText))),
                _StatusBadge(status: inv.status),
                IconButton(onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, color: kMuted)),
                IconButton(
                  onPressed: () async {
                    await context.read<AccountingState>().deleteArInvoice(inv.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, color: kRed)),
              ]),
              Text(inv.customerName, style: const TextStyle(fontSize: 14, color: kMuted)),
            ]),
          ),
          const Divider(color: kBorder),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [

            // Amounts
            Row(children: [
              Expanded(child: _AmountBox(label: t.subtotal2,   value: fmt.format(inv.subtotal),   color: kText)),
              const SizedBox(width: 10),
              Expanded(child: _AmountBox(label: t.sstAmt,        value: fmt.format(inv.sstAmount),  color: kMuted)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _AmountBox(label: 'Total',      value: fmt.format(inv.total),      color: kText)),
              const SizedBox(width: 10),
              Expanded(child: _AmountBox(label: 'Paid',       value: fmt.format(inv.amountPaid), color: kGreen)),
            ]),
            const SizedBox(height: 10),
            _AmountBox(label: t.balance, value: 'RM ${fmt.format(inv.balance)}',
              color: inv.balance > 0 ? kRed : kGreen, large: true),

            const SizedBox(height: 16),
            _DetailRow(t.issueDate, inv.issueDate),
            _DetailRow(t.dueDate2,   inv.dueDate),
            if (inv.notes?.isNotEmpty == true) _DetailRow(t.notes, inv.notes!),

            // Items
            if (inv.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t.items.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              ...inv.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.description, style: const TextStyle(fontSize: 13, color: kText)),
                    Text('${item.qty} × RM ${fmt.format(item.unitPrice)}',
                      style: const TextStyle(fontSize: 11, color: kMuted)),
                  ])),
                  Text('RM ${fmt.format(item.amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
                ]),
              )),
            ],

            // Record Payment
            if (inv.status != InvoiceStatus.paid && inv.status != InvoiceStatus.void_) ...[
              const SizedBox(height: 20),
              Text(t.recordPayment.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: _payCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: t.amtReceived,
                    prefixText: 'RM ',
                    filled: true, fillColor: kBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                )),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _paying ? null : _recordPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  child: _paying
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(t.record, style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}

// ── AR Invoice Form ───────────────────────────────────────────────────────────
class _ArInvoiceForm extends StatefulWidget {
  final ArInvoice? invoice;
  const _ArInvoiceForm({this.invoice});
  @override State<_ArInvoiceForm> createState() => _ArInvoiceFormState();
}

class _ArInvoiceFormState extends State<_ArInvoiceForm> {
  final _invNoCtrl   = TextEditingController();
  final _custCtrl    = TextEditingController();
  final _notesCtrl   = TextEditingController();
  String _issueDate  = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _dueDate    = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
  List<_LineItem> _items = [_LineItem()];
  bool _saving = false;

  @override
  void dispose() {
    _invNoCtrl.dispose();
    _custCtrl.dispose();
    _notesCtrl.dispose();
    for (final item in _items) item.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final inv = widget.invoice;
    if (inv != null) {
      _invNoCtrl.text  = inv.invNo;
      _custCtrl.text   = inv.customerName;
      _notesCtrl.text  = inv.notes ?? '';
      _issueDate       = inv.issueDate;
      _dueDate         = inv.dueDate;
      _items = inv.items.map((i) => _LineItem(
        desc: i.description,
        qty:  i.qty.toString(),
        price: i.unitPrice.toString(),
      )).toList();
    } else {
      _invNoCtrl.text = 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  double get _subtotal => _items.fold(0, (s, i) => s + i.amount);
  double get _sst      => 0; // can be extended with SST logic
  double get _total    => _subtotal + _sst;

  Future<void> _save() async {
    if (_saving || _invNoCtrl.text.isEmpty || _custCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    FocusManager.instance.primaryFocus?.unfocus();

    final inv = ArInvoice(
      id:           widget.invoice?.id ?? DateTime.now().millisecondsSinceEpoch,
      invNo:        _invNoCtrl.text.trim(),
      customerId:   _custCtrl.text.trim(),
      customerName: _custCtrl.text.trim(),
      issueDate:    _issueDate,
      dueDate:      _dueDate,
      subtotal:     _subtotal,
      sstAmount:    _sst,
      total:        _total,
      amountPaid:   widget.invoice?.amountPaid ?? 0,
      status:       widget.invoice?.status ?? InvoiceStatus.sent,
      notes:        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      items:        _items.where((i) => i.descVal.isNotEmpty).map((i) => ArInvoiceItem(
        description: i.descVal,
        qty:         double.tryParse(i.qtyVal) ?? 1,
        unitPrice:   double.tryParse(i.priceVal) ?? 0,
        amount:      i.amount,
      )).toList(),
    );

    await context.read<AccountingState>().saveArInvoice(inv);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final t   = L10n(context.read<AppState>().settings.lang);

    return DraggableScrollableSheet(
      initialChildSize: 0.94, maxChildSize: 0.97, minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
            child: Row(children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const Spacer(),
              Text(widget.invoice == null ? t.newInvoice : t.newInvoice,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context),
                child: Text(t.back, style: const TextStyle(color: kMuted))),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              _FormField(label: 'INVOICE NO *', child: _tf(_invNoCtrl, 'INV-001')),
              _FormField(label: 'CUSTOMER NAME *', child: _tf(_custCtrl, 'Customer name')),

              Row(children: [
                Expanded(child: _FormField(label: 'ISSUE DATE',
                  child: _DatePicker(value: _issueDate, onChanged: (d) => setState(() => _issueDate = d)))),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'DUE DATE',
                  child: _DatePicker(value: _dueDate, onChanged: (d) => setState(() => _dueDate = d)))),
              ]),

              // Line items
              Text(t.items.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              ..._items.asMap().entries.map((e) => _LineItemRow(
                item: e.value,
                onChanged: () => setState(() {}),
                onRemove: _items.length > 1 ? () => setState(() => _items.removeAt(e.key)) : null,
              )),
              TextButton.icon(
                onPressed: () => setState(() => _items.add(_LineItem())),
                icon: const Icon(Icons.add, size: 16),
                label: Text(t.addLine),
              ),

              const Divider(color: kBorder),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Subtotal: RM ${fmt.format(_subtotal)}', style: const TextStyle(fontSize: 13, color: kMuted)),
                  Text('Total: RM ${fmt.format(_total)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kText)),
                ]),
              ]),

              const SizedBox(height: 14),
              _FormField(label: 'NOTES', child: _tf(_notesCtrl, 'Optional notes...', maxLines: 2)),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kDark, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.invoice == null ? t.newInvoice : t.save,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _tf(TextEditingController ctrl, String hint, {int maxLines = 1}) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(fontSize: 14, color: kText),
    decoration: InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 13),
      filled: true, fillColor: kBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
  );
}

// ── Line item helpers ─────────────────────────────────────────────────────────
class _LineItem {
  String desc, qty, price;
  // Persistent controllers — created once, not on every rebuild
  late final TextEditingController descCtrl;
  late final TextEditingController qtyCtrl;
  late final TextEditingController priceCtrl;

  _LineItem({this.desc = '', this.qty = '1', this.price = '0'}) {
    descCtrl  = TextEditingController(text: desc);
    qtyCtrl   = TextEditingController(text: qty);
    priceCtrl = TextEditingController(text: price);
  }

  void dispose() {
    descCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }

  double get amount => (double.tryParse(qtyCtrl.text) ?? 0) * (double.tryParse(priceCtrl.text) ?? 0);
  String get descVal  => descCtrl.text;
  String get qtyVal   => qtyCtrl.text;
  String get priceVal => priceCtrl.text;
}

class _LineItemRow extends StatelessWidget {
  final _LineItem item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  const _LineItemRow({required this.item, required this.onChanged, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: TextField(
            controller: item.descCtrl,
            onChanged: (v) { item.desc = v; onChanged(); },
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(hintText: 'Description', border: InputBorder.none, isDense: true),
          )),
          if (onRemove != null) GestureDetector(onTap: onRemove,
            child: const Icon(Icons.close, size: 18, color: kMuted)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _miniField(item.qtyCtrl,   'Qty',        (v) { item.qty = v;   onChanged(); })),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _miniField(item.priceCtrl, 'Unit Price', (v) { item.price = v; onChanged(); })),
          const SizedBox(width: 8),
          Text('RM ${fmt.format(item.amount)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
        ]),
      ]),
    );
  }

  Widget _miniField(TextEditingController ctrl, String hint, ValueChanged<String> onChg) => TextField(
    controller: ctrl,
    onChanged: onChg,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(
      hintText: hint,
      filled: true, fillColor: kSurface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBorder)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      isDense: true,
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 2 — ACCOUNTS PAYABLE (mirrors AR structure)
// ════════════════════════════════════════════════════════════════════════════
class _ApTab extends StatefulWidget {
  const _ApTab();
  @override State<_ApTab> createState() => _ApTabState();
}

class _ApTabState extends State<_ApTab> {
  InvoiceStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final acc   = context.watch<AccountingState>();
    final fmt   = NumberFormat('#,##0.00');
    final t     = L10n(context.read<AppState>().settings.lang);
    final aging = acc.apAgingSummary;
    final list  = acc.apByStatus(_filter);

    return Column(children: [
      Container(
        color: kSurface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _SummaryChip(label: t.totalAp,  value: 'RM ${fmt.format(acc.totalPayable)}',   color: kRed),
          _SummaryChip(label: t.overdue,   value: 'RM ${fmt.format(acc.totalOverdueAp)}', color: Colors.orange),
          _SummaryChip(label: t.payable,     value: '${acc.apBills.length}',                color: kText),
        ]),
      ),
      if (aging.total > 0) _AgingBar(aging: aging, isAp: true),
      _FilterRow(selected: _filter, onSelect: (s) => setState(() => _filter = s)),
      Expanded(child: list.isEmpty
        ? _EmptyState(label: t.noTx, onAdd: () => _showApForm(context))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ApBillCard(
              bill: list[i],
              onTap: () => _showApDetail(context, list[i]),
            ),
          ),
      ),
    ]);
  }

  void _showApForm(BuildContext context, {ApBill? bill}) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccountingState>(),
        child: _ApBillForm(bill: bill),
      ),
    );
  }

  void _showApDetail(BuildContext context, ApBill bill) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AccountingState>(),
        child: _ApDetailSheet(bill: bill, onEdit: () {
          Navigator.pop(context);
          _showApForm(context, bill: bill);
        }),
      ),
    );
  }
}

// ── AP Bill Card ──────────────────────────────────────────────────────────────
class _ApBillCard extends StatelessWidget {
  final ApBill bill;
  final VoidCallback onTap;
  const _ApBillCard({required this.bill, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final s   = bill.status;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: s == InvoiceStatus.overdue ? kRedBd : kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(bill.billNo,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kText))),
            _StatusBadge(status: s),
          ]),
          const SizedBox(height: 4),
          Text(bill.supplierName, style: const TextStyle(fontSize: 13, color: kMuted)),
          const SizedBox(height: 8),
          Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total', style: TextStyle(fontSize: 10, color: kMuted)),
              Text('RM ${fmt.format(bill.total)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
            ]),
            const SizedBox(width: 24),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Balance', style: TextStyle(fontSize: 10, color: kMuted)),
              Text('RM ${fmt.format(bill.balance)}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                  color: bill.balance > 0 ? Colors.orange : kGreen)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Due', style: TextStyle(fontSize: 10, color: kMuted)),
              Text(bill.dueDate,
                style: TextStyle(fontSize: 12, color: bill.isOverdue ? kRed : kMuted)),
            ]),
          ]),
          if (bill.isOverdue) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(99)),
              child: Text('${bill.daysOverdue} days overdue',
                style: const TextStyle(fontSize: 11, color: kRed, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── AP Detail Sheet ───────────────────────────────────────────────────────────
class _ApDetailSheet extends StatefulWidget {
  final ApBill bill;
  final VoidCallback onEdit;
  const _ApDetailSheet({required this.bill, required this.onEdit});
  @override State<_ApDetailSheet> createState() => _ApDetailSheetState();
}

class _ApDetailSheetState extends State<_ApDetailSheet> {
  final _payCtrl = TextEditingController();
  bool _paying = false;

  Future<void> _recordPayment() async {
    final amt = double.tryParse(_payCtrl.text) ?? 0;
    if (amt <= 0) return;
    setState(() => _paying = true);
    await context.read<AccountingState>().recordApPayment(widget.bill.id, amt);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt  = NumberFormat('#,##0.00');
    final t    = L10n(context.read<AppState>().settings.lang);
    final bill = widget.bill;

    return DraggableScrollableSheet(
      initialChildSize: 0.65, maxChildSize: 0.95, minChildSize: 0.4,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(bill.billNo,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: kText))),
                _StatusBadge(status: bill.status),
                IconButton(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined, color: kMuted)),
                IconButton(
                  onPressed: () async {
                    await context.read<AccountingState>().deleteApBill(bill.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline, color: kRed)),
              ]),
              Text(bill.supplierName, style: const TextStyle(fontSize: 14, color: kMuted)),
            ]),
          ),
          const Divider(color: kBorder),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.all(20), children: [
            Row(children: [
              Expanded(child: _AmountBox(label: 'Total',   value: fmt.format(bill.total),      color: kText)),
              const SizedBox(width: 10),
              Expanded(child: _AmountBox(label: 'Paid',    value: fmt.format(bill.amountPaid), color: kGreen)),
            ]),
            const SizedBox(height: 10),
            _AmountBox(label: t.balance, value: 'RM ${fmt.format(bill.balance)}',
              color: bill.balance > 0 ? Colors.orange : kGreen, large: true),
            const SizedBox(height: 16),
            _DetailRow(t.issueDate, bill.issueDate),
            _DetailRow(t.dueDate2,   bill.dueDate),
            if (bill.category != null) _DetailRow('Category', bill.category!),
            if (bill.notes?.isNotEmpty == true) _DetailRow(t.notes, bill.notes!),

            if (bill.status != InvoiceStatus.paid && bill.status != InvoiceStatus.void_) ...[
              const SizedBox(height: 20),
              Text(t.recordPayment.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: _payCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: t.amtPaid, prefixText: 'RM ',
                    filled: true, fillColor: kBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                )),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _paying ? null : _recordPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  child: _paying
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(t.pay, style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ],
          ])),
        ]),
      ),
    );
  }
}

// ── AP Bill Form ──────────────────────────────────────────────────────────────
class _ApBillForm extends StatefulWidget {
  final ApBill? bill;
  const _ApBillForm({this.bill});
  @override State<_ApBillForm> createState() => _ApBillFormState();
}

class _ApBillFormState extends State<_ApBillForm> {
  final _billNoCtrl = TextEditingController();
  final _suppCtrl   = TextEditingController();
  final _amtCtrl    = TextEditingController();
  final _notesCtrl  = TextEditingController();
  String _issueDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String _dueDate   = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 30)));
  bool   _saving    = false;

  @override
  void initState() {
    super.initState();
    final b = widget.bill;
    if (b != null) {
      _billNoCtrl.text = b.billNo;
      _suppCtrl.text   = b.supplierName;
      _amtCtrl.text    = b.total.toString();
      _notesCtrl.text  = b.notes ?? '';
      _issueDate       = b.issueDate;
      _dueDate         = b.dueDate;
    } else {
      _billNoCtrl.text = 'BILL-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    }
  }

  Future<void> _save() async {
    if (_saving || _billNoCtrl.text.isEmpty || _suppCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final total = double.tryParse(_amtCtrl.text) ?? 0;
    final bill = ApBill(
      id:           widget.bill?.id ?? DateTime.now().millisecondsSinceEpoch,
      billNo:       _billNoCtrl.text.trim(),
      supplierId:   _suppCtrl.text.trim(),
      supplierName: _suppCtrl.text.trim(),
      issueDate:    _issueDate,
      dueDate:      _dueDate,
      subtotal:     total,
      sstAmount:    0,
      total:        total,
      amountPaid:   widget.bill?.amountPaid ?? 0,
      status:       widget.bill?.status ?? InvoiceStatus.sent,
      notes:        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await context.read<AccountingState>().saveApBill(bill);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n(context.read<AppState>().settings.lang);
    return DraggableScrollableSheet(
    initialChildSize: 0.88, maxChildSize: 0.97, minChildSize: 0.5,
    builder: (_, scroll) => Container(
      decoration: const BoxDecoration(
        color: kSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
            child: Row(children: [
              const Spacer(),
              Text(widget.bill == null ? t.newBill : t.newBill,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context),
                child: Text(t.back, style: const TextStyle(color: kMuted))),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _FormField(label: 'BILL NO *',         child: _tf(_billNoCtrl, 'BILL-001')),
              _FormField(label: 'SUPPLIER NAME *',   child: _tf(_suppCtrl,   'Supplier name')),
              _FormField(label: 'TOTAL AMOUNT (RM)', child: _tf(_amtCtrl,    '0.00', isNum: true)),
              Row(children: [
                Expanded(child: _FormField(label: 'ISSUE DATE',
                  child: _DatePicker(value: _issueDate, onChanged: (d) => setState(() => _issueDate = d)))),
                const SizedBox(width: 12),
                Expanded(child: _FormField(label: 'DUE DATE',
                  child: _DatePicker(value: _dueDate, onChanged: (d) => setState(() => _dueDate = d)))),
              ]),
              _FormField(label: 'NOTES', child: _tf(_notesCtrl, 'Optional notes...', maxLines: 2)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kDark, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                  child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(widget.bill == null ? t.newBill : t.save,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                )),
            ]),
          )),
        ]),
      ));
  }

  Widget _tf(TextEditingController ctrl, String hint, {int maxLines = 1, bool isNum = false}) =>
    TextField(
      controller: ctrl, maxLines: maxLines,
      keyboardType: isNum ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(fontSize: 14, color: kText),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: kMuted, fontSize: 13),
        filled: true, fillColor: kBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    );
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 3 — TRIAL BALANCE
// ════════════════════════════════════════════════════════════════════════════
class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab();

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final fmt  = NumberFormat('#,##0.00');
    final t = L10n(app.settings.lang);
    final bals = app.computeBalances();

    // Group by account type
    final groups = <String, List<MapEntry<String, double>>>{};
    for (final entry in bals.entries) {
      final acc  = accounts[entry.key];
      if (acc == null) continue;
      final type = _accType(entry.key);
      groups.putIfAbsent(type, () => []).add(entry);
    }

    double totalDr = 0, totalCr = 0;
    for (final e in bals.entries) {
      final acc = accounts[e.key];
      if (acc == null) continue;
      if (acc.normal == 'Dr') { totalDr += e.value.clamp(0, double.infinity); }
      else                    { totalCr += e.value.clamp(0, double.infinity); }
    }

    final balanced = (totalDr - totalCr).abs() < 0.01;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Balance indicator
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: balanced ? kGreenBg : kRedBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: balanced ? kGreenBd : kRedBd),
          ),
          child: Row(children: [
            Text(balanced ? '✅' : '⚠️', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(balanced ? t.booksBalanced : t.booksNotBal,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                  color: balanced ? kGreen : kRed)),
              Text('As of ${DateFormat('d MMM yyyy').format(DateTime.now())}',
                style: const TextStyle(fontSize: 12, color: kMuted)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: kDark, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Expanded(flex: 3, child: Text('Account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
            const Expanded(child: Text('Debit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.right)),
            const Expanded(child: Text('Credit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12), textAlign: TextAlign.right)),
          ]),
        ),
        const SizedBox(height: 8),

        // Groups
        for (final group in ['Asset', 'Liability', 'Equity', 'Revenue', 'Expense']) ...[
          if (groups[group] != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(group.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kMuted, letterSpacing: 0.8)),
            ),
            ...groups[group]!.map((e) {
              final acc = accounts[e.key]!;
              final isNormal = acc.normal == 'Dr';
              final dr = isNormal && e.value > 0 ? e.value : (!isNormal && e.value < 0 ? e.value.abs() : 0.0);
              final cr = !isNormal && e.value > 0 ? e.value : (isNormal && e.value < 0 ? e.value.abs() : 0.0);
              if (dr == 0 && cr == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: kSurface, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBorder)),
                child: Row(children: [
                  Expanded(flex: 3, child: Text(acc.name,
                    style: const TextStyle(fontSize: 12, color: kText))),
                  Expanded(child: Text(dr > 0 ? fmt.format(dr) : '—',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: dr > 0 ? kText : kMuted), textAlign: TextAlign.right)),
                  Expanded(child: Text(cr > 0 ? fmt.format(cr) : '—',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: cr > 0 ? kText : kMuted), textAlign: TextAlign.right)),
                ]),
              );
            }),
          ],
        ],

        // Totals
        const Divider(color: kBorder, thickness: 1.5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Expanded(flex: 3, child: Text('TOTAL',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: kText))),
            Expanded(child: Text('RM ${fmt.format(totalDr)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: kText),
              textAlign: TextAlign.right)),
            Expanded(child: Text('RM ${fmt.format(totalCr)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: kText),
              textAlign: TextAlign.right)),
          ]),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TAB 4 — GENERAL LEDGER
// ════════════════════════════════════════════════════════════════════════════
class _GeneralLedgerTab extends StatefulWidget {
  const _GeneralLedgerTab();
  @override State<_GeneralLedgerTab> createState() => _GeneralLedgerTabState();
}

class _GeneralLedgerTabState extends State<_GeneralLedgerTab> {
  String? _selectedAcc;

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final fmt  = NumberFormat('#,##0.00');
    final t = L10n(app.settings.lang);
    final bals = app.computeBalances();

    // Only show accounts with activity
    final activeAccounts = bals.entries
      .where((e) => e.value.abs() > 0.001 && accounts[e.key] != null)
      .toList()
      ..sort((a, b) => _accType(a.key).compareTo(_accType(b.key)));

    // Filter txs for selected account
    final selectedTxs = _selectedAcc == null ? <_GlEntry>[] :
      app.txs.expand<_GlEntry>((tx) => tx.entries
        .where((e) => e.acc == _selectedAcc)
        .map((e) => _GlEntry(tx: tx, entry: e))
      ).toList()
      ..sort((a, b) => b.tx.date.compareTo(a.tx.date));

    return Row(children: [
      // Left panel — account list
      Container(
        width: 140,
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(right: BorderSide(color: kBorder)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(t.accounts2.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: kMuted, letterSpacing: 0.6)),
          ),
          Expanded(child: ListView(children: activeAccounts.map((e) {
            final acc     = accounts[e.key]!;
            final isSelected = _selectedAcc == e.key;
            return GestureDetector(
              onTap: () => setState(() => _selectedAcc = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: isSelected ? kDark.withOpacity(0.08) : Colors.transparent,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(acc.name, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: isSelected ? kDark : kText),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(fmt.format(e.value.abs()),
                    style: TextStyle(fontSize: 10, color: isSelected ? kDark : kMuted)),
                ]),
              ),
            );
          }).toList())),
        ]),
      ),

      // Right panel — transactions
      Expanded(child: _selectedAcc == null
        ? Center(child: Text(t.selectAccount, style: TextStyle(color: kMuted, fontSize: 14)))
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: kSurface,
              child: Text(accounts[_selectedAcc]?.name ?? '',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: kText)),
            ),
            // Column headers
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: kBg,
              child: Row(children: const [
                Expanded(flex: 2, child: Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted))),
                Expanded(flex: 3, child: Text('Description', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted))),
                Expanded(child: Text('Dr', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted), textAlign: TextAlign.right)),
                Expanded(child: Text('Cr', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted), textAlign: TextAlign.right)),
              ]),
            ),
            Expanded(child: selectedTxs.isEmpty
              ? Center(child: Text(t.noEntries, style: TextStyle(color: kMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: selectedTxs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder),
                  itemBuilder: (_, i) {
                    final gl  = selectedTxs[i];
                    final isDr = gl.entry.dc == 'Dr';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Expanded(flex: 2, child: Text(gl.tx.date,
                          style: const TextStyle(fontSize: 11, color: kMuted))),
                        Expanded(flex: 3, child: Text(gl.tx.descEN,
                          style: const TextStyle(fontSize: 11, color: kText),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                        Expanded(child: Text(isDr ? fmt.format(gl.entry.val) : '—',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: isDr ? kText : kMuted), textAlign: TextAlign.right)),
                        Expanded(child: Text(!isDr ? fmt.format(gl.entry.val) : '—',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: !isDr ? kText : kMuted), textAlign: TextAlign.right)),
                      ]),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _GlEntry {
  final Transaction tx;
  final JournalEntry entry;
  const _GlEntry({required this.tx, required this.entry});
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ════════════════════════════════════════════════════════════════════════════
class _StatusBadge extends StatelessWidget {
  final InvoiceStatus status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final t = L10n(context.read<AppState>().settings.lang);
    final label = switch (status) {
      InvoiceStatus.draft   => t.draft,
      InvoiceStatus.sent    => t.sent,
      InvoiceStatus.partial => t.partial,
      InvoiceStatus.paid    => t.paid,
      InvoiceStatus.overdue => t.overdue,
      InvoiceStatus.void_   => t.void_,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text('${status.icon} $label',
        style: TextStyle(fontSize: 11, color: status.color, fontWeight: FontWeight.w700)),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
    Text(label, style: const TextStyle(fontSize: 9, color: kMuted)),
  ]));
}

class _AgingBar extends StatelessWidget {
  final AgingSummary aging;
  final bool isAp;
  const _AgingBar({required this.aging, this.isAp = false});

  @override
  Widget build(BuildContext context) {
    final fmt   = NumberFormat('#,##0');
    final t     = L10n(context.read<AppState>().settings.lang);
    final total = aging.total;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.agingAnalysis.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: kMuted, letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Row(children: [
          _AgingCell('Current',  aging.current,    const Color(0xFF4CAF50), total),
          _AgingCell('1-30d',    aging.days1to30,  const Color(0xFFFFEB3B), total),
          _AgingCell('31-60d',   aging.days31to60, const Color(0xFFFF9800), total),
          _AgingCell('61-90d',   aging.days61to90, const Color(0xFFF44336), total),
          _AgingCell('90d+',     aging.days90plus, const Color(0xFF9C27B0), total),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Row(children: [
            _AgingBar2(aging.current,     const Color(0xFF4CAF50), total),
            _AgingBar2(aging.days1to30,   const Color(0xFFFFEB3B), total),
            _AgingBar2(aging.days31to60,  const Color(0xFFFF9800), total),
            _AgingBar2(aging.days61to90,  const Color(0xFFF44336), total),
            _AgingBar2(aging.days90plus,  const Color(0xFF9C27B0), total),
          ]),
        ),
      ]),
    );
  }
}

class _AgingCell extends StatelessWidget {
  final String label;
  final double value, total;
  final Color color;
  const _AgingCell(this.label, this.value, this.color, this.total);
  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0');
    return Expanded(child: Column(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 8, color: kMuted)),
      Text(fmt.format(value), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kText)),
    ]));
  }
}

class _AgingBar2 extends StatelessWidget {
  final double value, total;
  final Color color;
  const _AgingBar2(this.value, this.color, this.total);
  @override
  Widget build(BuildContext context) {
    if (total == 0 || value == 0) return const SizedBox.shrink();
    return Expanded(
      flex: (value / total * 100).round().clamp(1, 100),
      child: Container(height: 8, color: color),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final InvoiceStatus? selected;
  final ValueChanged<InvoiceStatus?> onSelect;
  const _FilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Row(children: [
      _FilterChip(label: 'All',      selected: selected == null,                     onTap: () => onSelect(null)),
      _FilterChip(label: '📤 Sent',  selected: selected == InvoiceStatus.sent,       onTap: () => onSelect(InvoiceStatus.sent)),
      _FilterChip(label: '🔴 Overdue',selected: selected == InvoiceStatus.overdue,   onTap: () => onSelect(InvoiceStatus.overdue)),
      _FilterChip(label: '⏳ Partial',selected: selected == InvoiceStatus.partial,   onTap: () => onSelect(InvoiceStatus.partial)),
      _FilterChip(label: '✅ Paid',   selected: selected == InvoiceStatus.paid,      onTap: () => onSelect(InvoiceStatus.paid)),
      _FilterChip(label: '📝 Draft',  selected: selected == InvoiceStatus.draft,     onTap: () => onSelect(InvoiceStatus.draft)),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:  selected ? kDark : kSurface,
        border: Border.all(color: selected ? kDark : kBorder),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: selected ? Colors.white : kMuted)),
    ),
  );
}

class _AmountBox extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool large;
  const _AmountBox({required this.label, required this.value, required this.color, this.large = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: color.withOpacity(0.07), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: color)),
      Text(large ? value : 'RM $value',
        style: TextStyle(fontSize: large ? 16 : 14, fontWeight: FontWeight.w800, color: color)),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: kMuted)),
      const Spacer(),
      Text(value,  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
    ]),
  );
}

class _FormField extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormField({required this.label, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 6), child,
    ]),
  );
}

class _DatePicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _DatePicker({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () async {
      final d = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(value) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      );
      if (d != null) onChanged(DateFormat('yyyy-MM-dd').format(d));
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: kBg, border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_today_outlined, size: 15, color: kMuted),
        const SizedBox(width: 8),
        Text(value, style: const TextStyle(fontSize: 13, color: kText)),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final String label;
  final VoidCallback onAdd;
  const _EmptyState({required this.label, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final t = L10n(context.read<AppState>().settings.lang);
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('📄', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: onAdd,
        style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white),
        child: Text(t.save),
      ),
    ]));
  }
}
