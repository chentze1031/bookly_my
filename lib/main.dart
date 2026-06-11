import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'constants.dart';
import 'app_theme.dart';
import 'models.dart';
import 'state/app_state.dart';
import 'state/sub_state.dart';
import 'utils.dart';
import 'widgets/common.dart';
import 'screens/bill_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reports_transactions_screen.dart';
import 'screens/invoice_screen.dart';
import 'screens/payroll_screen.dart';
import 'screens/sub_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/bank_import_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/ai_screen.dart';
import 'services/supabase_service.dart';
import 'services/inventory_service.dart';
import 'state/accounting_state.dart';
import 'screens/accounting_screen.dart';
import 'screens/company_info_screen.dart';
import 'screens/settings_screen.dart';

// ─── Screens (inline compact versions) ───────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Android 15 edge-to-edge fix
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // FIX: initialize intl locales BEFORE any DateFormat/NumberFormat usage.
  // Without this, DateFormat('d MMM', 'en_MY') throws a MissingPluginException
  // or uninitialized locale error in release builds, causing HomeScreen to
  // render blank/grey after any state change that triggers a rebuild.
  await initializeDateFormatting('en_MY');
  await initializeDateFormatting('zh_MY');

  // Init Supabase
  await SupabaseService.initialize();

  final appState = AppState();
  final subState = SubState();
  await Future.wait([appState.init(), subState.init()]);

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: subState),
      ChangeNotifierProvider(create: (_) => InventoryState()),
      ChangeNotifierProvider(create: (_) => AccountingState()),
    ],
    child: const BooklyApp(),
  ));
}

// ════════════════════════════════════════════════════════════════════════════
// ROUTER
// ════════════════════════════════════════════════════════════════════════════
int _tabIndex(String loc) {
  if (loc.startsWith('/records')) return 1;
  if (loc.startsWith('/reports')) return 2;
  if (loc.startsWith('/accounting')) return 3;
  if (loc.startsWith('/inventory')) return 4;
  if (loc.startsWith('/settings')) return 5;
  return 0;
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: '/home',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AuthGate(child: _AppShell(child: child)),
      routes: [
        GoRoute(path: '/home', pageBuilder: (_, __) => const NoTransitionPage(child: _HomeTab())),
        GoRoute(path: '/records', pageBuilder: (_, __) => const NoTransitionPage(child: _RecordsTab())),
        GoRoute(path: '/reports', pageBuilder: (_, __) => const NoTransitionPage(child: _ReportsTab())),
        GoRoute(path: '/accounting', pageBuilder: (_, __) => const NoTransitionPage(child: _AccountingTab())),
        GoRoute(path: '/inventory', pageBuilder: (_, __) => const NoTransitionPage(child: _InventoryTab())),
        GoRoute(path: '/settings', pageBuilder: (_, __) => const NoTransitionPage(child: _SettingsTab())),
      ],
    ),
  ],
);

// ════════════════════════════════════════════════════════════════════════════
// ROOT APP
// ════════════════════════════════════════════════════════════════════════════
class BooklyApp extends StatelessWidget {
  const BooklyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _buildRouter(),
      title: 'Bookly MY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// APP SHELL — BottomNavigationBar via go_router
// ══════════════════════════════════════════════════════════════════════════
class _AppShell extends StatefulWidget {
  final Widget child;
  const _AppShell({super.key, required this.child});
  @override State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  void _showPaywall() => showSubSheet(context);

  void _showAddTx({String? type, Transaction? edit}) {
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

  void _showBill() => showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AccountingState>(),
      child: const BillFormSheet(),
    ),
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
    final loc  = GoRouterState.of(context).uri.toString();
    final idx  = _tabIndex(loc);

    final titles = [t.home, t.records, t.reports, t.accounting, t.inventory, t.settTitle];

    return Scaffold(
      appBar: (idx == 0) ? null : AppBar(
        title: Text(titles[idx]),
        actions: [if (sub.isPro) const Padding(padding: EdgeInsets.only(right: 14), child: ProBadge())],
      ),
      body: widget.child,
      floatingActionButton: (idx < 3) ? FloatingActionButton(
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
            type: BottomNavigationBarType.fixed,
            currentIndex: idx,
            onTap: (i) {
              const paths = ['/home', '/records', '/reports', '/accounting', '/inventory', '/settings'];
              context.go(paths[i]);
            },
            items: [
              BottomNavigationBarItem(icon: const Text('🏠', style: TextStyle(fontSize: 22)), label: t.home),
              BottomNavigationBarItem(icon: const Text('📋', style: TextStyle(fontSize: 22)), label: t.records),
              BottomNavigationBarItem(icon: const Text('📊', style: TextStyle(fontSize: 22)), label: t.reports),
              BottomNavigationBarItem(icon: const Text('📒', style: TextStyle(fontSize: 22)), label: t.accounting),
              BottomNavigationBarItem(icon: const Text('📦', style: TextStyle(fontSize: 22)), label: t.inventory),
              BottomNavigationBarItem(icon: const Text('⚙️', style: TextStyle(fontSize: 22)), label: t.settings),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tab wrappers ───────────────────────────────────────────────────────────
class _HomeTab extends StatelessWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_AppShellState>()!;
    return HomeScreen(
      onAddIncome:  () => shell._showAddTx(type: 'income'),
      onAddExpense: () => shell._showAddTx(type: 'expense'),
      onInvoice:    shell._showInvoice,
      onBill:       shell._showBill,
      onPayroll:    shell._showPayroll,
    );
  }
}

class _RecordsTab extends StatelessWidget {
  const _RecordsTab();
  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<_AppShellState>()!;
    return TransactionsScreen(
      key: const ValueKey('records'),
      onEdit: (tx) => shell._showAddTx(edit: tx),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();
  @override
  Widget build(BuildContext context) => const ReportsScreen();
}

class _AccountingTab extends StatelessWidget {
  const _AccountingTab();
  @override
  Widget build(BuildContext context) => const AccountingScreen();
}

class _InventoryTab extends StatelessWidget {
  const _InventoryTab();
  @override
  Widget build(BuildContext context) => const InventoryScreen(embedded: true);
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context) => const SettingsScreen();
}

// ════════════════════════════════════════════════════════════════════════════
// ADD / EDIT TRANSACTION SHEET
// ════════════════════════════════════════════════════════════════════════════
// Expense type groups (type_id, icon, enLabel, zhLabel)
const _expenseTypeGroups = [
  ('rent',  '🏢', 'Rental / Utilities',   '租金/水电'),
  ('mkt',   '📣', 'Marketing / Ads',       '广告/营销'),
  ('inv',   '📦', 'Inventory / Purchases', '进货/采购'),
  ('util',  '⚡', 'Utilities',             '水电费'),
  ('prof',  '⚖️', 'Professional Fees',     '专业服务费'),
  ('rep',   '🔧', 'Repairs / Maintenance', '维修维护'),
  ('ins',   '🛡️', 'Insurance',             '保险'),
  ('other', '💸', 'Other Expense',         '其他支出'),
];

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
  bool _saving = false; // FIX: prevents double-tap during async save
  String? _billTypeId; // selected expense type id before pay status

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

  // FIX: moved out of build() and made async.
  // Root cause of grey screen:
  //   (1) save() was a local void inside build() — called Navigator.pop(context)
  //       using the outer build context, NOT the DraggableScrollableSheet's
  //       inner context. Flutter couldn't find the right route to pop,
  //       leaving the modal barrier visible (solid grey screen).
  //   (2) addOrUpdateTx was not awaited — notifyListeners() fired AFTER pop,
  //       causing a rebuild race on a partially-dismissed route.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    // ── Step 1: dismiss keyboard FIRST ───────────────────────────────────────
    // Root cause of grey screen: autofocus TextField keeps keyboard open.
    // Calling Navigator.pop() while keyboard is visible triggers a MediaQuery
    // bottom-inset change mid-pop, which corrupts DraggableScrollableSheet's
    // internal state and leaves the modal barrier widget in the tree (grey screen).
    // Unfocusing closes the keyboard and settles the layout before we pop.
    FocusManager.instance.primaryFocus?.unfocus();

    final app     = context.read<AppState>();
    final sub     = context.read<SubState>();
    final parsed  = double.tryParse(_amtCtrl.text) ?? 0;
    final effCurr = _currency;
    final rate    = app.fxRates[_currency] ?? 1.0;
    final myrAmt  = parsed * rate;
    final sstRate = sstRates[_sstKey]?.rate ?? 0;
    final sstAmt  = myrAmt * sstRate;
    final total   = myrAmt + sstAmt;
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

    // ── Step 2: await DB write ────────────────────────────────────────────────
    await app.addOrUpdateTx(tx);
    if (!mounted) return;

    // ── Step 3: pop using the Navigator of THIS sheet's route ────────────────
    // Using Navigator.of(context) scoped to this widget ensures we only pop
    // the AddTxSheet route — never the parent MainShell.
    // canPop() guard prevents double-pop if user already dragged the sheet down.
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app  = context.watch<AppState>();
    final sub  = context.watch<SubState>();
    final t    = L10n(app.settings.lang);
    final isEd = widget.editTx != null;
    final cats = _type == 'income' ? incomeCategories : expenseCategories;

    final parsed  = double.tryParse(_amtCtrl.text) ?? 0;
    final effCurr = _currency;
    final rate    = app.fxRates[_currency] ?? 1.0;
    final myrAmt  = parsed * rate;
    final sstRate = sstRates[_sstKey]?.rate ?? 0;
    final sstAmt  = myrAmt * sstRate;
    final total   = myrAmt + sstAmt;
    final ready   = parsed > 0 && _cat != null && _date.isNotEmpty && _type != null;

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
                      if (_type == 'expense' && _billTypeId == null) ...[
                        // Grouped expense types (8 groups only)
                        GridView.count(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 3,
                          children: _expenseTypeGroups.map((g) => GestureDetector(
                            onTap: () => setState(() => _billTypeId = g.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                              decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(13)),
                              child: Row(children: [
                                Text(g.$2, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(app.settings.lang == 'zh' ? g.$4 : g.$3,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText))),
                              ]),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 10),
                        // Direct expense categories (salary, transport, etc.)
                        ...expenseCategories
                          .where((cat) => !cat.id.startsWith('bill_') && cat.id != 'ap_payment')
                          .map((cat) => GestureDetector(
                            onTap: () => setState(() { _cat = cat; _step = 3; }),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 9),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                              decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(13)),
                              child: Row(children: [
                                Text(cat.icon, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 10),
                                Expanded(child: Text(cat.label(app.settings.lang),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText))),
                              ]),
                            ),
                          )),
                        const SizedBox(height: 14),
                        _BackBtn(label: t.back, onTap: () => setState(() => _step = 1)),
                      ] else if (_type == 'expense' && _billTypeId != null) ...[
                        // Show pay status for selected bill type
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            Text(_expenseTypeGroups.firstWhere((g) => g.$1 == _billTypeId).$2,
                              style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Text(app.settings.lang == 'zh'
                              ? _expenseTypeGroups.firstWhere((g) => g.$1 == _billTypeId).$4
                              : _expenseTypeGroups.firstWhere((g) => g.$1 == _billTypeId).$3,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                          ]),
                        ),
                        Text(app.settings.lang == 'zh' ? '付款状态' : 'Payment Status',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
                        const SizedBox(height: 8),
                        for (final ps in [
                          ('unpaid', '⏳', 'Unpaid',      '未付款'),
                          ('cash',   '💵', 'Paid (Cash)',  '已付（现金）'),
                          ('bank',   '🏦', 'Paid (Bank)',  '已付（银行）'),
                        ]) GestureDetector(
                          onTap: () {
                            final catId = 'bill_${_billTypeId}_${ps.$1}';
                            final found = findCat(catId);
                            if (found != null) setState(() { _cat = found; _step = 3; });
                          },
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(13)),
                            child: Row(children: [
                              Text(ps.$2, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Text(app.settings.lang == 'zh' ? ps.$4 : ps.$3,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _BackBtn(label: t.back, onTap: () => setState(() => _billTypeId = null)),
                      ] else ...[
                        // Income categories (exclude invoice auto-generated ones)
                        GridView.count(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 3,
                          children: cats
                            .where((cat) => !cat.id.startsWith('inv_') && cat.id != 'ar_collect')
                            .map((cat) => GestureDetector(
                              onTap: () => setState(() { _cat = cat; _step = 3; }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                                decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(13)),
                                child: Row(children: [
                                  Text(cat.icon, style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(cat.label(app.settings.lang),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kText))),
                                ]),
                              ),
                            )).toList(),
                        ),
                        const SizedBox(height: 14),
                        _BackBtn(label: t.back, onTap: () => setState(() => _step = 1)),
                      ],
                    ],

                    // STEP 3 — details
                    if (_step == 3 && _cat != null) ...[
                      // Cat chip
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 1.5), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Container(width: 36, height: 36, decoration: BoxDecoration(color: _cat!.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
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
                        ]),
                        const SizedBox(height: 4),
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
                                Text('${currencyFlags[_currency] ?? ""} $_currency',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                                const Icon(Icons.expand_more, color: kMuted, size: 20),
                              ]),
                            ),
                          ),
                          if (_showCurrPicker)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12)]),
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
                        if (_currency != 'MYR' && parsed > 0) ...[
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
                              onPressed: () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                await context.read<AppState>().deleteTx(widget.editTx!.id);
                                if (!mounted) return;
                                final nav = Navigator.of(context);
                                if (nav.canPop()) nav.pop();
                              },
                              style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
                              child: Text(t.del),
                            ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: ElevatedButton(
  onPressed: (ready && !_saving) ? _save : null,
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
// END OF MAIN.DART
// ════════════════════════════════════════════════════════════════════════════
