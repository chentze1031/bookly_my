import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'models.dart';
import 'state/app_state.dart';
import 'state/sub_state.dart';
import 'utils.dart';
import 'widgets/common.dart';
import 'screens/home_screen.dart';
import 'screens/reports_transactions_screen.dart';
import 'screens/invoice_screen.dart';
import 'screens/payroll_screen.dart';

// ─── Screens (inline compact versions) ───────────────────────────────────────
export 'screens/home_screen.dart';
export 'screens/reports_transactions_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  // Init Supabase
  try {
    // Supabase init handled lazily in service
  } catch (_) {}

  final appState = AppState();
  final subState = SubState();
  await Future.wait([appState.init(), subState.init()]);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: subState),
    ],
    child: const BooklyApp(),
  ));
}

// ════════════════════════════════════════════════════════════════════════════
// ROOT APP
// ════════════════════════════════════════════════════════════════════════════
class BooklyApp extends StatelessWidget {
  const BooklyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    return MaterialApp(
      title: 'Bookly MY',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Helvetica Neue',
        colorScheme: ColorScheme.fromSeed(seedColor: kDark, brightness: Brightness.light),
        scaffoldBackgroundColor: kBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kText,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: kText, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.5),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: kSurface,
          selectedItemColor: kText,
          unselectedItemColor: kMuted,
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 10),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
      ),
      home: const MainShell(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MAIN SHELL — BottomNavigationBar
// ════════════════════════════════════════════════════════════════════════════
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  void _showPaywall() => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const PaywallSheet(),
  );

  void _showAddTx({String? type, Transaction? edit}) {
    final sub = context.read<SubState>();
    final app = context.read<AppState>();
    if (!sub.hasAccess && edit != null) { _showPaywall(); return; }
    if (!sub.hasAccess && app.thisMonthTxs.length >= 30) { _showPaywall(); return; }
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTxSheet(editTx: edit, prefillType: type),
    );
  }

  void _showInvoice() => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FullInvoiceSheet(),
  );

  void _showPayroll() => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const FullPayrollSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final sub  = context.watch<SubState>();
    final t    = L10n(app.settings.lang);

    final titles = [t.home, t.records, t.reports, t.settTitle];

    return Scaffold(
      appBar: _tab == 0 ? null : AppBar(
        title: Text(titles[_tab]),
        actions: [if (sub.isPro) const Padding(padding: EdgeInsets.only(right: 14), child: ProBadge())],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(
            onAddIncome:  () => _showAddTx(type: 'income'),
            onAddExpense: () => _showAddTx(type: 'expense'),
            onInvoice:    _showInvoice,
            onPayroll:    _showPayroll,
            onUpgrade:    _showPaywall,
          ),
          TransactionsScreen(
            onEdit:     (tx) => _showAddTx(edit: tx),
            onUpgrade:  _showPaywall,
          ),
          ReportsScreen(onUpgrade: _showPaywall),
          SettingsScreen(onUpgrade: _showPaywall),
        ],
      ),
      floatingActionButton: _tab != 3 ? FloatingActionButton(
        onPressed: () => _showAddTx(),
        backgroundColor: kDark,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 28),
      ) : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: kBorder),
          BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: [
              BottomNavigationBarItem(icon: const Text('🏠', style: TextStyle(fontSize: 22)), label: t.home),
              BottomNavigationBarItem(icon: const Text('📋', style: TextStyle(fontSize: 22)), label: t.records),
              BottomNavigationBarItem(icon: const Text('📊', style: TextStyle(fontSize: 22)), label: t.reports),
              BottomNavigationBarItem(icon: const Text('⚙️', style: TextStyle(fontSize: 22)), label: t.settings),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ADD / EDIT TRANSACTION SHEET
// ════════════════════════════════════════════════════════════════════════════
class AddTxSheet extends StatefulWidget {
  final Transaction? editTx;
  final String? prefillType;
  const AddTxSheet({super.key, this.editTx, this.prefillType});
  @override State<AddTxSheet> createState() => _AddTxSheetState();
}

class _AddTxSheetState extends State<AddTxSheet> {
  int _step = 1;
  String? _type;
  TxCategory? _cat;
  final _amtCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  String _currency = 'MYR';
  String _sstKey   = 'none';
  String _date     = nowISO();
  bool _showCurrPicker = false;
  bool _confirmDel = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editTx;
    if (e != null) {
      _step     = 3;
      _type     = e.type;
      _cat      = findCat(e.catId);
      _amtCtrl.text = e.origAmount.toString();
      _descCtrl.text = e.descEN;
      _currency = e.origCurrency;
      _sstKey   = e.sstKey;
      _date     = e.date;
    } else if (widget.prefillType != null) {
      _type = widget.prefillType;
      _step = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final sub  = context.watch<SubState>();
    final t    = L10n(app.settings.lang);
    final isEd = widget.editTx != null;
    final cats = _type == 'income' ? incomeCategories : expenseCategories;

    final parsed  = double.tryParse(_amtCtrl.text) ?? 0;
    final effCurr = sub.hasAccess ? _currency : 'MYR';
    final rate    = sub.hasAccess ? (app.fxRates[_currency] ?? 1.0) : 1.0;
    final myrAmt  = parsed * rate;
    final sstRate = sstRates[_sstKey]?.rate ?? 0;
    final sstAmt  = myrAmt * sstRate;
    final total   = myrAmt + sstAmt;
    final ready   = parsed > 0 && _cat != null && _date.isNotEmpty && _type != null;

    Future<void> save() async {
  if (!ready) return;

  final tx = Transaction(
    id:           widget.editTx?.id ?? DateTime.now().millisecondsSinceEpoch,
    type:         _type!,
    catId:        _cat!.id,
    amountMYR:    total,
    origAmount:   parsed,
    origCurrency: effCurr,
    sstKey:       _sstKey,
    sstMYR:       sstAmt,
    descEN:       _descCtrl.text.isNotEmpty ? _descCtrl.text : _cat!.enLabel,
    descZH:       _descCtrl.text.isNotEmpty ? _descCtrl.text : _cat!.zhLabel,
    date:         _date,
    entries:      _cat!.mkEntries(total),
  );

  await context.read<AppState>().addOrUpdateTx(tx);

  if (mounted) Navigator.pop(context);
}

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.5,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle + title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(99))),
                const SizedBox(height: 10),
                Text(isEd ? t.edit : t.newTx,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: kText)),
                const SizedBox(height: 8),
                // Step dots
                if (!isEd)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (int i = 1; i <= 3; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: i <= _step ? 24 : 8, height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _step ? kDark : kBorder,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                  ]),
              ]),
            ),
            // Steps
            Expanded(
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  children: [
                    // STEP 1 — type
                    if (_step == 1)
                      Row(children: [
                        _TypeCard(icon: '📥', label: t.moneyIn, color: kGreen, bg: kGreenBg, bd: kGreenBd, onTap: () => setState(() { _type='income'; _step=2; })),
                        const SizedBox(width: 12),
                        _TypeCard(icon: '📤', label: t.moneyOut, color: kRed, bg: kRedBg, bd: kRedBd, onTap: () => setState(() { _type='expense'; _step=2; })),
                      ]),

                    // STEP 2 — category
                    if (_step == 2) ...[
                      GridView.count(
                        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 3,
                        children: cats.map((c) => GestureDetector(
                          onTap: () => setState(() { _cat=c; _step=3; }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                            decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(13)),
                            child: Row(children: [
                              Text(c.icon, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(c.label(app.settings.lang),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText))),
                            ]),
                          ),
                        )).toList(),
                      ),
                      const SizedBox(height: 14),
                      _BackBtn(label: t.back, onTap: () => setState(() => _step = 1)),
                    ],

                    // STEP 3 — details
                    if (_step == 3 && _cat != null) ...[
                      // Cat chip
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Container(width: 36, height: 36, decoration: BoxDecoration(color: _cat!.color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: Center(child: Text(_cat!.icon, style: const TextStyle(fontSize: 20)))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_cat!.label(app.settings.lang), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
                            Text(_type == 'income' ? t.moneyIn : t.moneyOut, style: const TextStyle(fontSize: 11, color: kMuted)),
                          ])),
                          if (!isEd)
                            TextButton(onPressed: () => setState(() => _step = 2), child: Text(t.change, style: const TextStyle(color: kMuted, fontSize: 12))),
                        ]),
                      ),

                      // Currency (Pro only)
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(t.currency.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                          const SizedBox(width: 6),
                          if (!sub.hasAccess) const ProBadge(small: true),
                        ]),
                        const SizedBox(height: 4),
                        if (sub.hasAccess) ...[
                          GestureDetector(
                            onTap: () => setState(() => _showCurrPicker = !_showCurrPicker),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: kBg,
                                border: Border.all(color: _currency != 'MYR' ? kBlue : kBorder, width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('${currencyFlags[_currency] ?? ''} $_currency',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                                const Icon(Icons.expand_more, color: kMuted, size: 20),
                              ]),
                            ),
                          ),
                          if (_showCurrPicker)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12)]),
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: defaultRates.keys.map((cc) => GestureDetector(
                                    onTap: () => setState(() { _currency = cc; _showCurrPicker = false; }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                      decoration: BoxDecoration(
                                        color: _currency == cc ? kBlueBg : Colors.transparent,
                                        border: const Border(bottom: BorderSide(color: kBorder)),
                                      ),
                                      child: Row(children: [
                                        Text('${currencyFlags[cc]??''} ', style: const TextStyle(fontSize: 18)),
                                        const SizedBox(width: 8),
                                        Text(cc, style: TextStyle(color: _currency==cc?kBlue:kText, fontWeight: _currency==cc?FontWeight.w700:FontWeight.normal)),
                                        if (_currency == cc) ...[const Spacer(), const Text('✓', style: TextStyle(color: kBlue))],
                                      ]),
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ),
                        ] else
                          GestureDetector(
                            onTap: () { Navigator.pop(context); Future.delayed(const Duration(milliseconds: 100), () => context.read<SubState>()); /* showPaywall */ },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(color: kProBg, border: Border.all(color: kProBd, width: 1.5), borderRadius: BorderRadius.circular(12)),
                              child: const Row(children: [
                                Text('🔒 '), Text('MYR only on Free · Tap to upgrade', style: TextStyle(color: kPro, fontSize: 13, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        const SizedBox(height: 12),
                      ]),

                      // Amount
                      Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(effCurr, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kMuted)),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 180,
                            child: TextField(
                              controller: _amtCtrl,
                              autofocus: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '0.00', border: InputBorder.none,
                              ),
                              style: TextStyle(
                                fontSize: 44, fontWeight: FontWeight.w900,
                                color: _type == 'income' ? kGreen : kRed,
                                fontFamily: 'Georgia',
                              ),
                            ),
                          ),
                        ]),
                        Container(
                          height: 2, margin: const EdgeInsets.symmetric(horizontal: 32),
                          color: parsed > 0 ? _cat!.color : kBorder,
                        ),
                        if (sub.hasAccess && _currency != 'MYR' && parsed > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: kBlueBg, border: Border.all(color: kBlueBd), borderRadius: BorderRadius.circular(10)),
                            child: Column(children: [
                              Text('${fmtMYR(myrAmt)} = MYR', style: const TextStyle(fontWeight: FontWeight.w700, color: kBlue, fontSize: 13)),
                              Text('1 $_currency = RM ${rate.toStringAsFixed(4)}', style: const TextStyle(color: kMuted, fontSize: 11)),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ]),

                      // SST
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.sstLabel.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _sstKey,
                              items: sstRates.entries.map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value.enLabel))).toList(),
                              onChanged: (v) => setState(() => _sstKey = v!),
                            ),
                          ),
                        ),
                        if (sstAmt > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text('SST +${fmtMYR(sstAmt)} → Total: ${fmtMYR(total)}',
                              style: const TextStyle(fontSize: 12, color: kGold)),
                          ),
                        const SizedBox(height: 12),
                      ]),

                      // Description
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.description.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _descCtrl,
                          decoration: InputDecoration(
                            hintText: _cat!.label(app.settings.lang),
                            filled: true, fillColor: kBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder, width: 1.5)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ]),

                      // Date
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.date.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context, initialDate: DateTime.parse(_date),
                              firstDate: DateTime(2020), lastDate: DateTime(2030),
                            );
                            if (picked != null) setState(() => _date = picked.toIso8601String().substring(0, 10));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(_date, style: const TextStyle(fontSize: 14, color: kText)),
                              const Icon(Icons.calendar_today, size: 16, color: kMuted),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ]),

                      // Journal preview
                      if (parsed > 0 && _cat != null) ...[
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(color: kGoldBg, border: Border.all(color: kGoldBd), borderRadius: BorderRadius.circular(11)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.autoLbl.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kGold, letterSpacing: 0.5)),
                            const SizedBox(height: 5),
                            ..._cat!.mkEntries(total > 0 ? total : 1).map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                Text(e.dc, style: TextStyle(fontWeight: FontWeight.w700, color: e.dc=='Dr'?kBlue:kGreen, fontFamily: 'monospace', fontSize: 11)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(accounts[e.acc]?.name ?? '', style: const TextStyle(fontSize: 11, color: kMuted, fontFamily: 'monospace'))),
                                Text(fmtMYR(total), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                              ]),
                            )),
                          ]),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // Action buttons
                      Row(children: [
                        if (!isEd)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _BackBtn(label: t.back, onTap: () => setState(() => _step = 2)),
                          ),
                        if (isEd) ...[
                          if (!_confirmDel)
                            IconButton.outlined(
                              onPressed: () => setState(() => _confirmDel = true),
                              icon: const Icon(Icons.delete_outline, color: kRed),
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: kRedBd)),
                            )
                          else
                            OutlinedButton(
                              onPressed: () {
                                context.read<AppState>().deleteTx(widget.editTx!.id);
                                Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
                              child: Text(t.del),
                            ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton(
  onPressed: save, // ✅ 不用 ready
  style: ElevatedButton.styleFrom(
    backgroundColor: (_type=='income'?kGreen:kRed),
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13)),
    elevation: 0,
  ),
  child: Text(
    t.save,
    style: const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 15)),
),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String icon, label; final Color color, bg, bd; final VoidCallback onTap;
  const _TypeCard({required this.icon, required this.label, required this.color, required this.bg, required this.bd, required this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(color: bg, border: Border.all(color: bd, width: 2), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
        ]),
      ),
    ),
  );
}

class _BackBtn extends StatelessWidget {
  final String label; final VoidCallback onTap;
  const _BackBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(foregroundColor: kMuted, side: const BorderSide(color: kBorder),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SETTINGS SCREEN (inline)
// ════════════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  final VoidCallback onUpgrade;
  const SettingsScreen({super.key, required this.onUpgrade});
  @override State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final sub  = context.watch<SubState>();
    final t    = L10n(app.settings.lang);
    final s    = app.settings;

    void upd(AppSettings ns) => app.updateSettings(ns);

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 40),
      children: [
        // Subscription block
        if (sub.isPro)
          _ProBlock(sub: sub, t: t)
        else if (sub.dayPassActive)
          _DayPassBlock(exp: sub.dayPassExp!, t: t)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: GestureDetector(
              onTap: widget.onUpgrade,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  const Text('✦', style: TextStyle(fontSize: 28, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.proTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                    Text('${t.mPrice} · ${t.yPrice}', style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                  ])),
                  const Text('→', style: TextStyle(color: Colors.white, fontSize: 18)),
                ]),
              ),
            ),
          ),

        // Company
        SectionCard(
          title: '🏢 ${t.coName}',
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(children: [
              FieldInput(label: t.coName, placeholder: 'e.g. My Sdn Bhd', value: s.companyName, onChanged: (v) => upd(s.copyWith(companyName: v))),
              FieldInput(label: t.sstReg, placeholder: 'e.g. W10-1234-56789012', value: s.sstRegNo, onChanged: (v) => upd(s.copyWith(sstRegNo: v))),
              FieldInput(label: t.coReg, placeholder: 'e.g. 123456-X', value: s.coReg, onChanged: (v) => upd(s.copyWith(coReg: v))),
              FieldInput(label: t.coPhone, value: s.coPhone, onChanged: (v) => upd(s.copyWith(coPhone: v))),
              FieldInput(label: t.coEmail, value: s.coEmail, keyboard: TextInputType.emailAddress, onChanged: (v) => upd(s.copyWith(coEmail: v))),
              FieldInput(label: t.coAddr, value: s.coAddr, multiline: true, onChanged: (v) => upd(s.copyWith(coAddr: v))),
            ]),
          ),
        ),

        // Language
        SectionCard(
          title: '🌐 ${t.lang}',
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              for (final lng in [('en','EN'),('zh','中文')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => upd(s.copyWith(lang: lng.$1)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: s.lang == lng.$1 ? kDark : kBg,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: kBorder),
                      ),
                      child: Text(lng.$2, style: TextStyle(color: s.lang==lng.$1?Colors.white:kMuted, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                ),
            ]),
          ),
        ),

        // FX Rates
        SectionCard(
          title: '💱 ${t.fxLive}${!sub.hasAccess ? " 🔒" : ""}',
          child: sub.hasAccess
            ? Column(
                children: [
                  _FxStatusBar(app: app),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Wrap(
                      spacing: 6, runSpacing: 6,
                      children: defaultRates.keys.where((c) => c != 'MYR').map((code) =>
                        Container(
                          width: 130,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(9)),
                          child: Row(children: [
                            Text('${currencyFlags[code]??''} ', style: const TextStyle(fontSize: 13)),
                            Text(code, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text((app.fxRates[code]??0).toStringAsFixed(4),
                                style: const TextStyle(fontSize: 11, color: kText, fontFamily: 'monospace')),
                            ),
                          ]),
                        )
                      ).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: OutlinedButton.icon(
                      onPressed: app.resetFxRates,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(t.fxReset),
                    ),
                  ),
                ],
              )
            : Padding(padding: const EdgeInsets.all(13), child: LockBanner(onUpgrade: widget.onUpgrade)),
        ),

        // Cloud
        SectionCard(
          title: '☁️ ${t.cloudSync}${!sub.hasAccess?" 🔒":""}',
          child: sub.hasAccess
            ? Padding(
                padding: const EdgeInsets.all(13),
                child: Column(children: [
                  _SyncBtn(label: '☁️ ${t.cloudPull}', status: app.syncStatus, targetStatus: SyncStatus.pulling, onTap: () => app.pullCloud()),
                  const SizedBox(height: 10),
                  _SyncBtn(label: '⬆️ ${t.cloudPush}', status: app.syncStatus, targetStatus: SyncStatus.pushing, onTap: () => app.pushCloud(), color: kGreen),
                  if (app.syncError != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(app.syncError!, style: const TextStyle(color: kRed, fontSize: 12))),
                ]),
              )
            : Padding(padding: const EdgeInsets.all(13), child: LockBanner(onUpgrade: widget.onUpgrade)),
        ),

        // Export
        SectionCard(
          title: '📦 ${t.export}${!sub.hasAccess?" 🔒":""}',
          child: sub.hasAccess
            ? Padding(
                padding: const EdgeInsets.all(13),
                child: Column(children: [
                  _ExportBtn(icon: '📊', label: t.xlsExport, onTap: () { /* TODO: excel export */ }),
                  const SizedBox(height: 10),
                  _ExportBtn(icon: '💾', label: t.bakJson, onTap: () { /* TODO: json export */ }),
                ]),
              )
            : Padding(padding: const EdgeInsets.all(13), child: LockBanner(onUpgrade: widget.onUpgrade)),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text('Bookly MY', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText)),
            Text('v1.0 · Malaysia Edition · Flutter', style: TextStyle(fontSize: 11, color: kMuted)),
          ]),
        ),
      ],
    );
  }
}

class _ProBlock extends StatelessWidget {
  final SubState sub; final L10n t;
  const _ProBlock({required this.sub, required this.t});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('✦', style: TextStyle(fontSize: 24, color: Colors.white)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.proTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
          Text(t.monthly, style: const TextStyle(fontSize: 12, color: Color(0x99FFFFFF))),
        ]),
        const Spacer(),
        const ProBadge(),
      ]),
      if (sub.proExpires != null) ...[
        const SizedBox(height: 8),
        Text('${t.proExpires}: ${sub.proExpires}', style: const TextStyle(fontSize: 11, color: Color(0x80FFFFFF))),
      ],
      const SizedBox(height: 10),
      Text(t.manageSub, style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 12, decoration: TextDecoration.underline)),
    ]),
  );
}

class _DayPassBlock extends StatelessWidget {
  final int exp; final L10n t;
  const _DayPassBlock({required this.exp, required this.t});
  @override
  Widget build(BuildContext context) {
    final expTime = DateTime.fromMillisecondsSinceEpoch(exp);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kGoldBg, border: Border.all(color: kGoldBd, width: 1.5), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t.dayActive, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: kGold)),
        Text('${expTime.hour.toString().padLeft(2,'0')}:${expTime.minute.toString().padLeft(2,'0')} ${expTime.day}/${expTime.month}/${expTime.year}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
      ]),
    );
  }
}

class _FxStatusBar extends StatelessWidget {
  final AppState app;
  const _FxStatusBar({required this.app});
  @override
  Widget build(BuildContext context) {
    final ok = app.fxStatus == FxStatus.ok;
    final err = app.fxStatus == FxStatus.error;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? kGreenBg : err ? kRedBg : kBg,
        border: Border.all(color: ok ? kGreenBd : err ? kRedBd : kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(app.fxStatus == FxStatus.loading ? '⏳ Fetching…' : ok ? '✓ Live rates' : '⚠ Offline',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ok?kGreen:err?kRed:kMuted)),
          if (app.fxUpdatedAt != null) Text('Updated: ${app.fxUpdatedAt}', style: const TextStyle(fontSize: 10, color: kMuted)),
        ])),
        ElevatedButton(
          onPressed: app.fxStatus == FxStatus.loading ? null : app.fetchFxRates,
          style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('↺', style: TextStyle(fontSize: 14)),
        ),
      ]),
    );
  }
}

class _SyncBtn extends StatelessWidget {
  final String label; final SyncStatus status; final SyncStatus targetStatus; final VoidCallback onTap; final Color? color;
  const _SyncBtn({required this.label, required this.status, required this.targetStatus, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final loading = status == targetStatus;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onTap,
        icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const SizedBox.shrink(),
        label: Text(loading ? 'Syncing…' : label),
        style: ElevatedButton.styleFrom(
          backgroundColor: loading ? kBorder : (color ?? kDark),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          elevation: 0,
        ),
      ),
    );
  }
}

class _ExportBtn extends StatelessWidget {
  final String icon, label; final VoidCallback onTap;
  const _ExportBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Text(icon, style: const TextStyle(fontSize: 18)),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: kText, side: const BorderSide(color: kBorder),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// PAYWALL SHEET
// ════════════════════════════════════════════════════════════════════════════
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});
  @override State<PaywallSheet> createState() => _PaywallState();
}

class _PaywallState extends State<PaywallSheet> {
  int _tab = 0; // 0=plans, 1=daypass
  bool _yearly = true;
  bool _buying  = false;
  bool _restoring = false;

  @override
  Widget build(BuildContext context) {
    final sub  = context.watch<SubState>();
    final app  = context.watch<AppState>();
    final t    = L10n(app.settings.lang);
    final adsLeft = (3 - sub.adsToday).clamp(0, 3);

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.96),
      child: Column(
        children: [
          // Dark header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(children: [
              Row(children: [
                const Text('📒', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.proTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
                  Text(t.proSub, style: const TextStyle(fontSize: 13, color: Color(0xA6FFFFFF))),
                ])),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                    child: const Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 16))),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              // Tabs
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(99)),
                child: Row(
                  children: [
                    for (final tab in [('💎 Plans', 0), ('📺 Free Day Pass', 1)])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tab = tab.$2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _tab == tab.$2 ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(tab.$1, textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                                color: _tab==tab.$2 ? const Color(0xFF3B0764) : Colors.white.withOpacity(0.7))),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              child: _tab == 0
                ? _PlansTab(t: t, yearly: _yearly, buying: _buying, restoring: _restoring,
                    onSelectPlan: (y) => setState(() => _yearly = y),
                    onBuy: () async {
                      setState(() => _buying = true);
                      final ok = await sub.purchasePlan(_yearly);
                      setState(() => _buying = false);
                      if (ok && mounted) Navigator.pop(context);
                    },
                    onRestore: () async {
                      setState(() => _restoring = true);
                      final ok = await sub.restorePurchases();
                      setState(() => _restoring = false);
                      if (ok && mounted) Navigator.pop(context);
                    })
                : _AdPassTab(t: t, sub: sub),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlansTab extends StatelessWidget {
  final L10n t; final bool yearly, buying, restoring;
  final ValueChanged<bool> onSelectPlan;
  final VoidCallback onBuy, onRestore;
  const _PlansTab({required this.t, required this.yearly, required this.buying,
    required this.restoring, required this.onSelectPlan, required this.onBuy, required this.onRestore});

  @override
  Widget build(BuildContext context) => Column(children: [
    // Plan cards
    Row(children: [
      for (final plan in [
        (true, t.yearly,  t.yPrice, t.ySave),
        (false, t.monthly, t.mPrice, null),
      ])
        Expanded(
          child: GestureDetector(
            onTap: () => onSelectPlan(plan.$1),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  margin: EdgeInsets.only(right: plan.$1 ? 5 : 0, left: plan.$1 ? 0 : 5),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                  decoration: BoxDecoration(
                    color: yearly == plan.$1 ? kProBg : kSurface,
                    border: Border.all(color: yearly==plan.$1?kPro:kBorder, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(children: [
                    Text(plan.$2, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.4)),
                    const SizedBox(height: 3),
                    Text(plan.$3, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: yearly==plan.$1?kPro:kText, fontFamily: 'Georgia')),
                    if (yearly == plan.$1) ...[const SizedBox(height: 6), const ProBadge(small: true)],
                  ]),
                ),
                if (plan.$4 != null)
                  Positioned(
                    top: -10, left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(99)),
                      child: Text(plan.$4!, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
          ),
        ),
    ]),
    const SizedBox(height: 16),
    // Feature list
    Container(
      decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: L10n.features.asMap().entries.map((e) {
          final i = e.key; final f = e.value;
          final isZh = t.isZh;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: i < L10n.features.length - 1 ? const Border(bottom: BorderSide(color: kBorder)) : null,
            ),
            child: Row(children: [
              SizedBox(width: 26, child: Text(f.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18))),
              const SizedBox(width: 12),
              Expanded(child: Text(isZh ? f.$3 : f.$2, style: const TextStyle(fontSize: 13, color: kText))),
              const Text('✓', style: TextStyle(color: kGreen, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          );
        }).toList(),
      ),
    ),
    const SizedBox(height: 16),
    // Buy button
    SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: buying ? null : onBuy,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPro, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: buying
          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
          : Text(yearly ? t.subY : t.subM, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      ),
    ),
    const SizedBox(height: 10),
    SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: restoring ? null : onRestore,
        style: OutlinedButton.styleFrom(foregroundColor: kMuted, side: const BorderSide(color: kBorder),
          padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: Text(restoring ? t.syncing : t.restore),
      ),
    ),
    const SizedBox(height: 12),
    const Text('Subscriptions auto-renew. Cancel anytime in Google Play.',
      textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: kMuted)),
  ]);
}

class _AdPassTab extends StatelessWidget {
  final L10n t; final SubState sub;
  const _AdPassTab({required this.t, required this.sub});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: kGoldBg, border: Border.all(color: kGoldBd, width: 1.5), borderRadius: BorderRadius.circular(16)),
    child: Column(children: [
      Row(children: [
        const Text('📺', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.adPass, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kGold)),
          Text(t.adDesc, style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
        ])),
      ]),
      const SizedBox(height: 14),
      // Progress dots
      Row(children: List.generate(3, (i) => Expanded(
        child: Container(
          margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
          height: 8,
          decoration: BoxDecoration(
            color: i < sub.adsToday ? const Color(0xFFD97706) : kBorder,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ))),
      const SizedBox(height: 10),
      Text('${t.adPass}: ${sub.adsToday}/3${sub.adsToday < 3 ? " · ${3-sub.adsToday} left" : ""}',
        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
      const SizedBox(height: 12),
      if (sub.dayPassActive)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(10)),
          child: const Text('🎉 Day Pass Active!', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        )
      else if (sub.adsToday >= 3)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(10)),
          child: const Text('🎉 Day Pass Unlocked!', textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
        )
      else
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: sub.adLoading ? null : () => sub.watchRewardedAd(),
            icon: sub.adLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('📺', style: TextStyle(fontSize: 18)),
            label: Text(sub.adLoading ? 'Loading…' : t.watchAd),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
    ]),
  );
}

// needed by settings
extension on L10n {
  String get proExpires => isZh ? '到期时间' : 'Expires';
}
  
