import 'package:flutter/material.dart';
import 'models.dart';

// ─── Design ───────────────────────────────────────────────────────────────────
const kBg      = Color(0xFFF5F4F0);
const kSurface = Color(0xFFFFFFFF);
const kBorder  = Color(0xFFE8E4DE);
const kText    = Color(0xFF18160F);
const kMuted   = Color(0xFF9B9084);

const kGreen   = Color(0xFF15803D);
const kGreenBg = Color(0xFFF0FDF4);
const kGreenBd = Color(0xFF86EFAC);

const kRed     = Color(0xFFB91C1C);
const kRedBg   = Color(0xFFFEF2F2);
const kRedBd   = Color(0xFFFCA5A5);

const kGold    = Color(0xFF92400E);
const kGoldBg  = Color(0xFFFFFBEB);
const kGoldBd  = Color(0xFFFCD34D);

const kBlue    = Color(0xFF1D4ED8);
const kBlueBg  = Color(0xFFEFF6FF);
const kBlueBd  = Color(0xFF93C5FD);

const kPro     = Color(0xFF7C3AED);
const kProBg   = Color(0xFFFAF5FF);
const kProBd   = Color(0xFFC4B5FD);

const kDark    = Color(0xFF18160F);

// ─── Malaysia SST ─────────────────────────────────────────────────────────────
class SstRate {
  final String enLabel;
  final String zhLabel;
  final double rate;
  const SstRate(this.enLabel, this.zhLabel, this.rate);
}

const sstRates = <String, SstRate>{
  'none':     SstRate('No Tax',         '免税',        0.00),
  'sst5':     SstRate('Sales Tax 5%',   '销售税 5%',   0.05),
  'sst10':    SstRate('Sales Tax 10%',  '销售税 10%',  0.10),
  'service6': SstRate('Service Tax 6%', '服务税 6%',   0.06),
  'service8': SstRate('Service Tax 8%', '服务税 8%',   0.08),
};

// ─── EPF / SOCSO / EIS (2026) ─────────────────────────────────────────────────
double epfEe(double g)   => g * 0.11;
double epfEr(double g)   => g <= 5000 ? g * 0.13 : g * 0.12;
double socsoEe(double g) => (g * 0.005).clamp(0, 14.10);
double socsoEr(double g) => (g * 0.0175).clamp(0, 49.40);
double eisEe(double g)   => (g * 0.002).clamp(0, 3.90);
double eisEr(double g)   => (g * 0.004).clamp(0, 7.90);

// ─── Statutory annual leave (Malaysia Employment Act) ─────────────────────────
// Entitlement by completed years of service: <2y → 8, 2–5y → 12, >5y → 16 days.
int statutoryAnnualLeave(int yearsOfService) {
  if (yearsOfService < 2) return 8;
  if (yearsOfService <= 5) return 12;
  return 16;
}

// ─── FX Defaults ─────────────────────────────────────────────────────────────
const defaultRates = <String, double>{
  'MYR': 1.0,   'USD': 4.72,  'CNY': 0.65,  'SGD': 3.52,
  'EUR': 5.15,  'GBP': 6.10,  'JPY': 0.031, 'KRW': 0.0034,
  'AUD': 3.02,  'HKD': 0.61,  'THB': 0.135, 'IDR': 0.00029,
  'PHP': 0.082, 'INR': 0.057, 'TWD': 0.148, 'SAR': 1.26, 'AED': 1.29,
};

const currencyFlags = <String, String>{
  'MYR': '🇲🇾', 'USD': '🇺🇸', 'CNY': '🇨🇳', 'SGD': '🇸🇬',
  'EUR': '🇪🇺', 'GBP': '🇬🇧', 'JPY': '🇯🇵', 'KRW': '🇰🇷',
  'AUD': '🇦🇺', 'HKD': '🇭🇰', 'THB': '🇹🇭', 'IDR': '🇮🇩',
  'PHP': '🇵🇭', 'INR': '🇮🇳', 'TWD': '🇹🇼', 'SAR': '🇸🇦', 'AED': '🇦🇪',
};

// ─── Accounts ─────────────────────────────────────────────────────────────────
class Account {
  final String name;
  final String normal;
  const Account(this.name, this.normal);
}

const accounts = <String, Account>{
  '1010': Account('Cash',                'Dr'),
  '1020': Account('Bank Account',        'Dr'),
  '1100': Account('Accounts Receivable', 'Dr'),
  '1200': Account('Inventory',           'Dr'),
  '2010': Account('Accounts Payable',    'Cr'),
  '4010': Account('Sales Revenue',       'Cr'),
  '4020': Account('Service Revenue',     'Cr'),
  '4030': Account('Other Income',        'Cr'),
  '5010': Account('Cost of Goods Sold',  'Dr'),
  '5100': Account('Salaries & Wages',    'Dr'),
  '5110': Account('Rent',                'Dr'),
  '5120': Account('Utilities',           'Dr'),
  '5130': Account('Office Supplies',     'Dr'),
  '5140': Account('Marketing',           'Dr'),
  '5150': Account('Insurance',           'Dr'),
  '5160': Account('Meals',               'Dr'),
  '5170': Account('Travel',              'Dr'),
  '5180': Account('Professional Fees',   'Dr'),
  '5190': Account('Repairs',             'Dr'),
  '5200': Account('Other Expenses',      'Dr'),
  '5210': Account('Transport & Fuel',    'Dr'),
  '5220': Account('Purchases',           'Dr'),
};

// ─── Categories ───────────────────────────────────────────────────────────────
class TxCategory {
  final String id;
  final String icon;
  final Color  color;
  final String enLabel;
  final String zhLabel;
  final String type;
  final List<JournalEntry> Function(double) mkEntries;

  const TxCategory({
    required this.id, required this.icon, required this.color,
    required this.enLabel, required this.zhLabel, required this.type,
    required this.mkEntries,
  });

  String label(String lang) => lang == 'zh' ? zhLabel : enLabel;
}

// ── Invoice payment method entries (used by Invoice screen) ─────────────────
// Unpaid:  Dr 1100 AR      / Cr 4010 Revenue
// Cash:    Dr 1010 Cash    / Cr 4010 Revenue
// Bank:    Dr 1020 Bank    / Cr 4010 Revenue
List<JournalEntry> invoiceEntries(double a, String payMode) => switch (payMode) {
  'cash' => [JournalEntry(acc:'1010',dc:'Dr',val:a), JournalEntry(acc:'4010',dc:'Cr',val:a)],
  'bank' => [JournalEntry(acc:'1020',dc:'Dr',val:a), JournalEntry(acc:'4010',dc:'Cr',val:a)],
  _      => [JournalEntry(acc:'1100',dc:'Dr',val:a), JournalEntry(acc:'4010',dc:'Cr',val:a)],
};

// ── Bill payment method entries (used by Bill screen) ────────────────────────
List<JournalEntry> billEntries(double a, String expenseAcc, String payMode) => switch (payMode) {
  'cash' => [JournalEntry(acc:expenseAcc, dc:'Dr',val:a), JournalEntry(acc:'1010',dc:'Cr',val:a)],
  'bank' => [JournalEntry(acc:expenseAcc, dc:'Dr',val:a), JournalEntry(acc:'1020',dc:'Cr',val:a)],
  _      => [JournalEntry(acc:expenseAcc, dc:'Dr',val:a), JournalEntry(acc:'2010',dc:'Cr',val:a)],
};

// ── Bill expense type mapping ─────────────────────────────────────────────────
const billExpenseTypes = <Map<String, String>>[
  {'id': 'rent',         'icon': '🏢', 'en': 'Rental / Utilities',    'zh': '租金/水电',   'acc': '5110'},
  {'id': 'salary',       'icon': '👤', 'en': 'Salaries',              'zh': '薪资',        'acc': '5100'},
  {'id': 'marketing',    'icon': '📣', 'en': 'Marketing / Ads',       'zh': '广告/营销',   'acc': '5140'},
  {'id': 'transport',    'icon': '🚗', 'en': 'Transport / Fuel',      'zh': '交通/油费',   'acc': '5210'},
  {'id': 'inventory',    'icon': '📦', 'en': 'Inventory / Purchases', 'zh': '进货',        'acc': '1200'},
  {'id': 'professional', 'icon': '💼', 'en': 'Professional Fees',     'zh': '专业费用',    'acc': '5180'},
  {'id': 'supplies',     'icon': '📎', 'en': 'Office Supplies',       'zh': '办公用品',    'acc': '5130'},
  {'id': 'repairs',      'icon': '🔧', 'en': 'Repairs / Maintenance', 'zh': '维修保养',    'acc': '5190'},
  {'id': 'insurance',    'icon': '🛡', 'en': 'Insurance',             'zh': '保险',        'acc': '5150'},
  {'id': 'other',        'icon': '💸', 'en': 'Other Expense',         'zh': '其他支出',    'acc': '5200'},
];

final incomeCategories = <TxCategory>[
  TxCategory(id:'product_sale', icon:'📦', color:kGreen,           enLabel:'Product Sale',    zhLabel:'产品销售',  type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4010',dc:'Cr',val:a)]),
  TxCategory(id:'service_sale', icon:'🛠', color:Color(0xFF059669), enLabel:'Service',         zhLabel:'服务/咨询', type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4020',dc:'Cr',val:a)]),
  TxCategory(id:'other_income', icon:'💰', color:Color(0xFF0891B2), enLabel:'Other Income',    zhLabel:'其他收入',  type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4030',dc:'Cr',val:a)]),
  TxCategory(id:'ar_collect',   icon:'🧾', color:Color(0xFF0D9488), enLabel:'Payment In (AR)', zhLabel:'收款入账',  type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'1100',dc:'Cr',val:a)]),
  TxCategory(id:'ar_invoice', icon:'🧾', color:kBlue, enLabel:'Invoice (AR)', zhLabel:'发票(应收)', type:'income', mkEntries:(a)=>[JournalEntry(acc:'1100',dc:'Dr',val:a),JournalEntry(acc:'4010',dc:'Cr',val:a)]),
];

final expenseCategories = <TxCategory>[
  // ── Bill workflow (auto-generated, do not show in Add Expense) ────────────
  // bill_*_unpaid:  Dr Expense / Cr 2010 AP
  // bill_*_cash:    Dr Expense / Cr 1010 Cash
  // bill_*_bank:    Dr Expense / Cr 1020 Bank
  // ap_payment:     Dr 2010 AP / Cr 1020 Bank
  TxCategory(id:'bill_rent_unpaid',  icon:'🏢', color:Color(0xFFEA580C), enLabel:'Rent Bill (Unpaid)',      zhLabel:'租金(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5110',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_rent_cash',    icon:'🏢', color:Color(0xFFEA580C), enLabel:'Rent Bill (Cash)',        zhLabel:'租金(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5110',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_rent_bank',    icon:'🏢', color:Color(0xFFEA580C), enLabel:'Rent Bill (Bank)',        zhLabel:'租金(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5110',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_mkt_unpaid',   icon:'📣', color:Color(0xFF9333EA), enLabel:'Marketing Bill (Unpaid)', zhLabel:'广告(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5140',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_mkt_cash',     icon:'📣', color:Color(0xFF9333EA), enLabel:'Marketing Bill (Cash)',   zhLabel:'广告(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5140',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_mkt_bank',     icon:'📣', color:Color(0xFF9333EA), enLabel:'Marketing Bill (Bank)',   zhLabel:'广告(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5140',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_inv_unpaid',   icon:'📦', color:Color(0xFFB45309), enLabel:'Inventory Bill (Unpaid)', zhLabel:'进货(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'1200',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_inv_cash',     icon:'📦', color:Color(0xFFB45309), enLabel:'Inventory Bill (Cash)',   zhLabel:'进货(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'1200',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_inv_bank',     icon:'📦', color:Color(0xFFB45309), enLabel:'Inventory Bill (Bank)',   zhLabel:'进货(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'1200',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_util_unpaid',  icon:'⚡', color:Color(0xFFCA8A04), enLabel:'Utilities Bill (Unpaid)', zhLabel:'水电(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5120',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_util_cash',    icon:'⚡', color:Color(0xFFCA8A04), enLabel:'Utilities Bill (Cash)',   zhLabel:'水电(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5120',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_util_bank',    icon:'⚡', color:Color(0xFFCA8A04), enLabel:'Utilities Bill (Bank)',   zhLabel:'水电(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5120',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_prof_unpaid',  icon:'⚖', color:Color(0xFF4F46E5), enLabel:'Prof. Fees (Unpaid)',     zhLabel:'专业费(未付)', type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5180',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_prof_cash',    icon:'⚖', color:Color(0xFF4F46E5), enLabel:'Prof. Fees (Cash)',       zhLabel:'专业费(现金)', type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5180',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_prof_bank',    icon:'⚖', color:Color(0xFF4F46E5), enLabel:'Prof. Fees (Bank)',       zhLabel:'专业费(银行)', type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5180',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_rep_unpaid',   icon:'🔧', color:Color(0xFF475569), enLabel:'Repairs (Unpaid)',        zhLabel:'维修(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5190',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_rep_cash',     icon:'🔧', color:Color(0xFF475569), enLabel:'Repairs (Cash)',          zhLabel:'维修(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5190',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_rep_bank',     icon:'🔧', color:Color(0xFF475569), enLabel:'Repairs (Bank)',          zhLabel:'维修(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5190',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_ins_unpaid',   icon:'🛡', color:kBlue,             enLabel:'Insurance (Unpaid)',      zhLabel:'保险(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5150',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_ins_cash',     icon:'🛡', color:kBlue,             enLabel:'Insurance (Cash)',        zhLabel:'保险(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5150',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_ins_bank',     icon:'🛡', color:kBlue,             enLabel:'Insurance (Bank)',        zhLabel:'保险(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5150',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'bill_other_unpaid', icon:'💸', color:Color(0xFF64748B), enLabel:'Other Expense (Unpaid)',  zhLabel:'其他(未付)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5200',dc:'Dr',val:a),JournalEntry(acc:'2010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_other_cash',   icon:'💸', color:Color(0xFF64748B), enLabel:'Other Expense (Cash)',    zhLabel:'其他(现金)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5200',dc:'Dr',val:a),JournalEntry(acc:'1010',dc:'Cr',val:a)]),
  TxCategory(id:'bill_other_bank',   icon:'💸', color:Color(0xFF64748B), enLabel:'Other Expense (Bank)',    zhLabel:'其他(银行)',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5200',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'ap_payment',        icon:'💳', color:Color(0xFFEA580C), enLabel:'AP Payment',             zhLabel:'付款出账',    type:'expense', mkEntries:(a)=>[JournalEntry(acc:'2010',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  // ── Direct cash expense ───────────────────────────────────────────────────
  TxCategory(id:'salary',        icon:'👤', color:kRed,              enLabel:'Salaries',         zhLabel:'工资薪酬',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5100',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'rent',          icon:'🏢', color:Color(0xFFEA580C), enLabel:'Rent',             zhLabel:'租金',       type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5110',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'utilities',     icon:'⚡', color:Color(0xFFCA8A04), enLabel:'Utilities',        zhLabel:'水电费',     type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5120',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'supplies',      icon:'📎', color:Color(0xFF7C3AED), enLabel:'Office Supplies',  zhLabel:'办公用品',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5130',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'marketing',     icon:'📣', color:Color(0xFF9333EA), enLabel:'Marketing',        zhLabel:'营销广告',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5140',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'insurance',     icon:'🛡', color:kBlue,             enLabel:'Insurance',        zhLabel:'保险',       type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5150',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'meals',         icon:'🍽', color:Color(0xFFDB2777), enLabel:'Meals',            zhLabel:'餐饮招待',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5160',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'travel',        icon:'✈', color:Color(0xFF0284C7), enLabel:'Travel',           zhLabel:'差旅费',     type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5170',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'professional',  icon:'⚖', color:Color(0xFF4F46E5), enLabel:'Professional Fees',zhLabel:'专业服务费', type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5180',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'repairs',       icon:'🔧', color:Color(0xFF475569), enLabel:'Repairs',          zhLabel:'维修维护',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5190',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'cogs',          icon:'🏭', color:Color(0xFFB45309), enLabel:'Cost of Goods',    zhLabel:'商品成本',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5010',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
  TxCategory(id:'other_expense', icon:'💸', color:Color(0xFF64748B), enLabel:'Other Expense',    zhLabel:'其他支出',   type:'expense', mkEntries:(a)=>[JournalEntry(acc:'5200',dc:'Dr',val:a),JournalEntry(acc:'1020',dc:'Cr',val:a)]),
];

TxCategory? findCat(String id) {
  try {
    return [...incomeCategories, ...expenseCategories].firstWhere((c) => c.id == id);
  } catch (_) { return null; }
}

// User-selectable categories: exclude auto-generated bill / AP / AR workflow
// variants (e.g. bill_rent_cash, ap_payment, ar_invoice) that should never be
// picked manually. Used by Add Tx, Budget, and Recurring.
final userExpenseCategories = expenseCategories
    .where((c) => !c.id.startsWith('bill_') && c.id != 'ap_payment')
    .toList();
final userIncomeCategories = incomeCategories
    .where((c) => !c.id.startsWith('ar_'))
    .toList();

// The expense (Dr) account a category posts to — used to aggregate spend
// across a category's bill variants for budgeting.
String drAccountOf(TxCategory c) {
  final e = c.mkEntries(1);
  return e.firstWhere((j) => j.dc == 'Dr', orElse: () => e.first).acc;
}

// ─── i18n ─────────────────────────────────────────────────────────────────────

// ── Storage Keys ────────────────────────────────────────────────────────────
abstract class StorageKeys {
  static const settings    = 'bly_settings';
  static const offlineQueue = 'bly_offline_queue';
  static const invoices    = 'bly_invoices';
  static const payrolls    = 'bly_payrolls';
  static const arInvoices  = 'bly_ar_invoices';
  static const quotations  = 'bly_quotations';
  static const deliveryOrders = 'bly_delivery_orders';
  static const creditNotes = 'bly_credit_notes';
  static const leave       = 'bly_leave';
  static const purchaseOrders = 'bly_purchase_orders';
  static const budgets     = 'bly_budgets';
  static const recurring   = 'bly_recurring';
  static const warehouses  = 'bly_warehouses';
  static const apBills     = 'bly_ap_bills';
  static const suppliers   = 'bly_suppliers';
  static const fxCached    = 'bly_fx_cache';
  static const fxTimestamp = 'bly_fx_ts';
}
class L10n {
  final String lang;
  const L10n(this.lang);

  bool get isZh => lang == 'zh';
  bool get isMs => lang == 'ms';
  // Trilingual picker: English / 中文 / Bahasa Melayu.
  String _t(String en, String zh, String ms) =>
      lang == 'zh' ? zh : lang == 'ms' ? ms : en;

  // Navigation
  String get appName    => 'Bookly MY';
  String get home       => _t('Home', '首页', 'Utama');
  String get records    => _t('Records', '记录', 'Rekod');
  String get reports    => _t('Reports', '报表', 'Laporan');
  String get accounting => _t('Accounting', '账务', 'Perakaunan');

  // Accounting module
  String get receivable     => _t('Receivable', '应收账款', 'Belum Terima');
  String get payable        => _t('Payable', '应付账款', 'Belum Bayar');
  String get trialBalance   => _t('Trial Balance', '试算表', 'Imbangan Duga');
  String get generalLedger  => _t('General Ledger', '总账', 'Lejar Am');
  String get newInvoice     => _t('New Invoice', '新增发票', 'Invois Baharu');
  String get newBill        => _t('New Bill', '新增账单', 'Bil Baharu');
  String get bill           => _t('Bill', '账单', 'Bil');
  String get billType       => _t('Expense Type', '费用类型', 'Jenis Perbelanjaan');
  String get payStatus      => _t('Payment Status', '付款状态', 'Status Bayaran');
  String get unpaid         => _t('Unpaid', '未付款', 'Belum Bayar');
  String get paidCash       => _t('Paid (Cash)', '已付（现金）', 'Dibayar (Tunai)');
  String get paidBank       => _t('Paid (Bank)', '已付（银行）', 'Dibayar (Bank)');
  String get supplierName   => _t('Supplier Name', '供应商名称', 'Nama Pembekal');
  String get billNo         => _t('Bill No.', '账单号', 'No. Bil');
  String get transport      => _t('Transport / Fuel', '交通/油费', 'Pengangkutan / Minyak');
  String get addBill        => _t('Add Bill', '添加账单', 'Tambah Bil');
  String get invIssued      => _t('Invoice Issued', '开发票', 'Invois Dikeluarkan');
  String get invCollected   => _t('Invoice Collected', '收款', 'Bayaran Diterima');
  String get billReceived   => _t('Bill Received', '收到账单', 'Bil Diterima');
  String get apPayment      => _t('AP Payment', '付款出账', 'Bayaran Belum Bayar');
  String get totalAr        => _t('Total AR', '应收总额', 'Jumlah Belum Terima');
  String get totalAp        => _t('Total AP', '应付总额', 'Jumlah Belum Bayar');
  String get overdue        => _t('Overdue', '逾期', 'Tertunggak');
  String get current        => _t('Current', '未逾期', 'Semasa');
  String get daysOverdue    => _t('days overdue', '天逾期', 'hari tertunggak');
  String get recordPayment  => _t('Record Payment', '记录付款', 'Rekod Bayaran');
  String get amtReceived    => _t('Amount received', '收到金额', 'Jumlah diterima');
  String get amtPaid        => _t('Amount paid', '付出金额', 'Jumlah dibayar');
  String get record         => _t('Record', '记录', 'Rekod');
  String get pay            => _t('Pay', '付款', 'Bayar');
  String get issueDate      => _t('Issue Date', '开单日期', 'Tarikh Keluar');
  String get dueDate2       => _t('Due Date', '到期日', 'Tarikh Akhir');
  String get supplier       => _t('Supplier', '供应商', 'Pembekal');
  String get suppliers      => _t('Suppliers', '供应商管理', 'Pembekal');
  String get newSupplier    => _t('New Supplier', '新增供应商', 'Pembekal Baharu');
  String get booksBalanced  => _t('Books are balanced', '账目平衡', 'Akaun seimbang');
  String get booksNotBal    => _t('Books are NOT balanced', '账目不平衡', 'Akaun TIDAK seimbang');
  String get agingAnalysis  => _t('Aging Analysis', '账龄分析', 'Analisis Penuaan');
  String get selectAccount  => _t('← Select an account', '← 选择科目', '← Pilih akaun');
  String get noEntries      => _t('No entries', '暂无记录', 'Tiada rekod');
  String get accounts2      => _t('Accounts', '科目', 'Akaun');
  String get draft          => _t('Draft', '草稿', 'Draf');
  String get sent           => _t('Sent', '已发送', 'Dihantar');
  String get partial        => _t('Partial', '部分收款', 'Separa');
  String get paid           => _t('Paid', '已付清', 'Dibayar');
  String get void_          => _t('Void', '已作废', 'Batal');
  String get balance        => _t('Balance', '余额', 'Baki');
  String get subtotal2      => _t('Subtotal', '小计', 'Jumlah Kecil');
  String get sstAmt         => _t('SST', 'SST 金额', 'SST');
  String get items          => _t('Items', '项目', 'Item');
  String get addLine        => _t('Add Line', '+ 添加项目', '+ Tambah Baris');
  String get description2   => _t('Description', '描述', 'Penerangan');
  String get qty            => _t('Qty', '数量', 'Kuantiti');
  String get unitPrice      => _t('Unit Price', '单价', 'Harga Seunit');
  String get settings   => _t('Settings', '设置', 'Tetapan');


  // Home
  String get netProfit  => _t('Net Profit', '净利润', 'Untung Bersih');
  String get income     => _t('Income', '收入', 'Pendapatan');
  String get expenses   => _t('Expenses', '支出', 'Perbelanjaan');
  String get addIncome  => _t('Add Income', '添加收入', 'Tambah Pendapatan');
  String get addExpense => _t('Add Expense', '添加支出', 'Tambah Perbelanjaan');
  String get topSpend   => _t('Top Spending', '主要支出', 'Perbelanjaan Utama');
  String get recent     => _t('Recent', '最近记录', 'Terkini');

  // List/filter
  String get all        => _t('All', '全部', 'Semua');
  String get noTx       => _t('No transactions', '暂无记录', 'Tiada transaksi');
  String get search     => _t('Search…', '搜索…', 'Cari…');
  String get allTime    => _t('All time', '全部时间', 'Semua masa');

  // Reports
  String get pl         => _t('Profit & Loss', '损益表', 'Untung & Rugi');
  String get bs         => _t('Balance Sheet', '资产负债表', 'Kunci Kira-kira');
  String get sstRep     => _t('SST Report', 'SST 报告', 'Laporan SST');
  String get revenue    => _t('Revenue', '收入', 'Hasil');
  String get cogs       => _t('Cost of Goods', '商品成本', 'Kos Barang');
  String get grossP     => _t('Gross Profit', '毛利润', 'Untung Kasar');
  String get opex       => _t('Operating Expenses', '运营费用', 'Perbelanjaan Operasi');
  String get totalEx    => _t('Total Expenses', '总支出', 'Jumlah Perbelanjaan');
  String get totalRev   => _t('Total Revenue', '总收入', 'Jumlah Hasil');
  String get assets     => _t('Assets', '资产', 'Aset');
  String get liab       => _t('Liabilities', '负债', 'Liabiliti');
  String get equity     => _t('Net Worth', '净资产', 'Nilai Bersih');
  String get cashBank   => _t('Cash in Bank', '银行存款', 'Tunai di Bank');
  String get ar         => _t('Accounts Receivable', '应收账款', 'Akaun Belum Terima');
  String get inventory  => _t('Inventory', '库存', 'Inventori');
  String get ap         => _t('Accounts Payable', '应付账款', 'Akaun Belum Bayar');

  // SST report
  String get sstCollected => _t('SST Collected', '已收 SST', 'SST Dikutip');
  String get sstPaid      => _t('SST Paid', '已付 SST', 'SST Dibayar');
  String get sstNet       => _t('Net SST', '净 SST', 'SST Bersih');

  // Add Tx form
  String get moneyIn    => _t('Money In', '收款', 'Wang Masuk');
  String get moneyOut   => _t('Money Out', '付款', 'Wang Keluar');
  String get description=> _t('Description (optional)', '备注（可选）', 'Penerangan (pilihan)');
  String get date       => _t('Date', '日期', 'Tarikh');
  String get currency   => _t('Currency', '货币', 'Mata Wang');
  String get sstLabel   => _t('SST / Tax', 'SST / 税率', 'SST / Cukai');
  String get back       => _t('Back', '返回', 'Kembali');
  String get change     => _t('Change', '更改', 'Tukar');
  String get save       => _t('Save', '保存', 'Simpan');
  String get edit       => _t('Edit Transaction', '编辑记录', 'Sunting Transaksi');
  String get newTx      => _t('New Transaction', '新增记录', 'Transaksi Baharu');
  String get autoLbl    => _t('Auto-recorded as', '自动计入账目', 'Auto-direkod sebagai');
  String get fxRate     => _t('Rate', '汇率', 'Kadar');
  String get del        => _t('Delete', '删除', 'Padam');
  String get keep       => _t('Keep', '保留', 'Simpan');

  // FX
  String get fxLive     => _t('Live rates', '实时汇率', 'Kadar langsung');
  String get fxReset    => _t('Reset to defaults', '恢复默认', 'Set semula');

  // Settings
  String get settTitle  => _t('Settings', '设置', 'Tetapan');
  String get coName     => _t('Company Name', '公司名称', 'Nama Syarikat');
  String get coReg      => _t('Company Reg No.', '公司注册号', 'No. Pendaftaran Syarikat');
  String get sstReg     => _t('SST Reg. No.', 'SST 注册号', 'No. Pendaftaran SST');
  String get coAddr     => _t('Address', '地址', 'Alamat');
  String get coPhone    => _t('Phone', '电话', 'Telefon');
  String get coEmail    => _t('Email', '邮箱', 'E-mel');
  String get langLabel  => _t('Language', '语言', 'Bahasa');

  // Cloud
  String get cloudSync  => _t('Cloud Sync', '云端同步', 'Penyegerakan Awan');
  String get cloudPull  => _t('Pull from cloud', '从云端加载', 'Tarik dari awan');
  String get cloudPush  => _t('Push to cloud', '推送到云端', 'Hantar ke awan');
  String get syncing    => _t('Syncing…', '同步中…', 'Menyegerak…');
  String get export     => _t('Export', '导出', 'Eksport');
  String get xlsExport  => _t('Export Excel', '导出 Excel', 'Eksport Excel');
  String get bakJson    => _t('Export JSON Backup', '导出 JSON 备份', 'Eksport Sandaran JSON');
  String get restJson   => _t('Restore from JSON', '从 JSON 恢复', 'Pulih dari JSON');

  // Invoice payment status (non-duplicate aliases)
  String get invUnpaid    => _t('Unpaid (AR)', '客户未付款', 'Belum Bayar (AR)');
  String get invCash      => _t('Paid - Cash', '现金收款', 'Dibayar - Tunai');
  String get invBank      => _t('Paid - Bank', '银行转账收款', 'Dibayar - Bank');
  String get billSaved    => _t('Bill saved', '账单已保存', 'Bil disimpan');
  String get cashPay      => _t('Cash', '现金', 'Tunai');
  String get bankPay      => _t('Bank Transfer', '银行转账', 'Pindahan Bank');

  // Invoice
  String get invoice    => _t('Invoice Manager', '发票管理', 'Pengurus Invois');
  String get invNo      => _t('Invoice No.', '发票号码', 'No. Invois');
  String get invDate    => _t('Invoice Date', '发票日期', 'Tarikh Invois');
  String get dueDate    => _t('Due Date', '到期日', 'Tarikh Akhir');
  String get billTo     => _t('Bill To', '客户', 'Bil Kepada');
  String get subTotal   => _t('Subtotal', '小计', 'Jumlah Kecil');
  String get grandTotal => _t('TOTAL DUE', '总计', 'JUMLAH PERLU BAYAR');
  String get bankName   => _t('Bank Name', '银行', 'Nama Bank');
  String get bankAcct   => _t('Account No.', '账号', 'No. Akaun');
  String get notes      => _t('Notes', '备注', 'Nota');
  String get terms      => _t('Terms & Conditions', '条款', 'Terma & Syarat');
  String get sharePrint => _t('Share / Print', '分享 / 打印', 'Kongsi / Cetak');
  String get logo       => _t('Company Logo', '公司 Logo', 'Logo Syarikat');
  String get sig        => _t('E-Signature', '电子签名', 'E-Tandatangan');
  String get drawSig    => _t('Draw', '手写签名', 'Lukis');
  String get clearSig   => _t('Clear', '清除', 'Kosongkan');
  String get saveSig    => _t('Save Signature', '保存签名', 'Simpan Tandatangan');

  // Quotation
  String get quotation    => _t('Quotation Manager', '报价单管理', 'Pengurus Sebut Harga');
  String get newQuotation => _t('New Quotation', '新增报价单', 'Sebut Harga Baharu');
  String get quotHistory  => _t('Quotation History', '报价单记录', 'Sejarah Sebut Harga');
  String get quotNo       => _t('Quotation No.', '报价单号', 'No. Sebut Harga');
  String get quotDate     => _t('Quotation Date', '报价日期', 'Tarikh Sebut Harga');
  String get validUntil   => _t('Valid Until', '有效期至', 'Sah Sehingga');
  String get convertToInv => _t('Convert to Invoice', '转为发票', 'Tukar ke Invois');
  String get accepted     => _t('Accepted', '已接受', 'Diterima');
  String get rejected     => _t('Rejected', '已拒绝', 'Ditolak');
  String get converted    => _t('Converted', '已转发票', 'Ditukar');

  // Delivery Order
  String get deliveryOrder   => _t('Delivery Order', '送货单管理', 'Nota Penghantaran');
  String get newDeliveryOrder=> _t('New Delivery Order', '新增送货单', 'Nota Penghantaran Baharu');
  String get doHistory       => _t('Delivery Order History', '送货单记录', 'Sejarah Nota Penghantaran');
  String get doNo            => _t('D.O. No.', '送货单号', 'No. D.O.');
  String get doDate          => _t('Delivery Date', '送货日期', 'Tarikh Penghantaran');
  String get deliverTo       => _t('Deliver To', '送货至', 'Hantar Kepada');
  String get refInvoice      => _t('Ref. Invoice', '关联发票', 'Invois Rujukan');
  String get convertToDo     => _t('To D.O.', '转送货单', 'Ke D.O.');
  String get receivedBy      => _t('Received By', '收货人签名', 'Diterima Oleh');
  String get delivered       => _t('Delivered', '已送达', 'Dihantar');
  String get deliveryDriver  => _t('Delivery Driver (optional)', '送货员（可选）', 'Pemandu Penghantaran (pilihan)');
  String get selectInvoice   => _t('Select Invoice', '选择发票', 'Pilih Invois');
  String get noInvoices      => _t('No invoices yet', '暂无发票', 'Tiada invois lagi');

  // Purchase Order
  String get purchaseOrder    => _t('Purchase Order', '采购单管理', 'Pesanan Belian');
  String get newPurchaseOrder => _t('New Purchase Order', '新增采购单', 'Pesanan Belian Baharu');
  String get poHistory        => _t('Purchase Orders', '采购单记录', 'Pesanan Belian');
  String get poNo             => _t('P.O. No.', '采购单号', 'No. P.O.');
  String get poDate           => _t('Order Date', '采购日期', 'Tarikh Pesanan');
  String get receiveStock     => _t('Receive', '收货入库', 'Terima');
  String get poReceived       => _t('Received', '已收货', 'Diterima');
  String get poOrdered        => _t('Ordered', '已下单', 'Dipesan');

  // Credit Note
  String get creditNote     => _t('Credit Note', '信用备注管理', 'Nota Kredit');
  String get newCreditNote  => _t('New Credit Note', '新增信用备注', 'Nota Kredit Baharu');
  String get cnHistory      => _t('Credit Notes', '信用备注记录', 'Nota Kredit');
  String get cnNo           => _t('Credit Note No.', '信用备注号', 'No. Nota Kredit');
  String get cnDate         => _t('Date', '日期', 'Tarikh');
  String get creditReason   => _t('Reason', '退款/调整原因', 'Sebab');
  String get convertToCn    => _t('To C/N', '转信用备注', 'Ke C/N');
  String get totalCredit    => _t('TOTAL CREDIT', '信用总额', 'JUMLAH KREDIT');
  String get arReduced      => _t('AR reduced', '应收已冲减', 'AR dikurangkan');

  // Customer
  String get customers  => _t('Customers', '客户管理', 'Pelanggan');
  String get newCust    => _t('New Customer', '新增客户', 'Pelanggan Baharu');
  String get custName   => _t('Company / Name', '公司 / 名称', 'Syarikat / Nama');
  String get custReg    => _t('Reg No.', '注册号', 'No. Pendaftaran');
  String get custSST    => _t('SST Reg No.', 'SST 注册号', 'No. Pendaftaran SST');
  String get custAddr   => _t('Address', '地址', 'Alamat');
  String get custPhone  => _t('Phone', '电话', 'Telefon');
  String get custEmail  => _t('Email', '邮箱', 'E-mel');

  // Employee
  String get employees  => _t('Employees', '员工管理', 'Pekerja');
  String get newEmp     => _t('Add Employee', '新增员工', 'Tambah Pekerja');
  String get empName    => _t('Full Name', '姓名', 'Nama Penuh');
  String get empIC      => _t('IC No.', 'IC 号码', 'No. IC');
  String get empPos     => _t('Position', '职位', 'Jawatan');
  String get empDept    => _t('Department', '部门', 'Jabatan');
  String get empBasic   => _t('Basic Salary (MYR)', '基本薪资 (MYR)', 'Gaji Pokok (MYR)');
  String get empEPF     => 'EPF No.';
  String get empSOCSO   => 'SOCSO No.';
  String get empBank    => _t('Bank', '银行', 'Bank');
  String get empAcct    => _t('Account No.', '账号', 'No. Akaun');

  // Payroll
  String get payroll    => _t('Payroll', '薪资管理', 'Gaji');
  String get payEmp     => _t('Employee', '员工', 'Pekerja');
  String get selEmp     => _t('Select Employee', '选择员工', 'Pilih Pekerja');
  String get payPeriod  => _t('Pay Period', '薪资期间', 'Tempoh Gaji');
  String get earnings   => _t('Earnings', '收入项目', 'Pendapatan');
  String get statutory  => _t('Statutory', '法定缴款', 'Caruman Berkanun');
  String get otherDed   => _t('Other Deductions', '其他扣款', 'Potongan Lain');
  String get grossPay   => _t('Gross Pay', '总薪资', 'Gaji Kasar');
  String get netPay     => _t('Net Pay', '实发薪资', 'Gaji Bersih');
  String get totalDed   => _t('Total Deductions', '总扣款', 'Jumlah Potongan');
  String get totalCost  => _t('Total Employer Cost', '雇主总成本', 'Jumlah Kos Majikan');

  // Subscription
  String get proTitle   => 'Bookly PRO';
  String get proSub     => _t('Unlock all features', '解锁所有高级功能', 'Buka semua ciri');
  String get monthly    => _t('Monthly', '按月订阅', 'Bulanan');
  String get yearly     => _t('Yearly', '按年订阅', 'Tahunan');
  String get restore    => _t('Restore Purchases', '恢复购买', 'Pulih Pembelian');
  String get watchAd    => _t('Watch Ad', '看广告', 'Tonton Iklan');
  String get adPass     => _t('Free Day Pass', '免费日通行证', 'Pas Harian Percuma');
  String get adDesc     => _t('Watch 3 ads to unlock 24 hours', '观看3个广告，解锁24小时', 'Tonton 3 iklan untuk buka 24 jam');
  String get proLocked  => _t('Pro Feature', 'Pro 专属功能', 'Ciri Pro');
  String get proUnlock  => _t('Upgrade to unlock', '升级 Pro 解锁', 'Naik taraf untuk buka');
  String get freePlan   => _t('Free Plan', '免费版', 'Pelan Percuma');
  String get proExpires => _t('Expires', '到期时间', 'Tamat Tempoh');
  String get manageSub  => _t('Manage Subscription', '管理订阅', 'Urus Langganan');
  String get dayActive  => _t('📺 Day Pass active until', '📺 日通行证有效至', '📺 Pas Harian sah sehingga');

  // Misc
  String get reminder   => _t(
    'SST threshold: RM 500k/year · e-Invoice above RM 1M',
    'SST 门槛：年营业额 RM50万 · 超 RM100万须电子发票',
    'Ambang SST: RM500k/tahun · e-Invois melebihi RM1J');

  static const features = [
    ('🚫', 'No ads — ever',                     '永久去除所有广告'),
    ('♾️', 'Unlimited transactions',            '无限记录笔数'),
    ('🧾', 'Tax invoices + quotations',         '税务发票 + 报价单'),
    ('🚚', 'Delivery orders',                   '送货单'),
    ('↩️', 'Credit notes (auto-adjust AR)',     '信用备注（自动冲减应收）'),
    ('📈', 'Customer spending analytics',       '顾客消费分析'),
    ('💼', 'Payroll + payslip generator',       '薪资 + 工资单生成'),
    ('🇲🇾', 'CP39 · EPF/SOCSO/EIS · EA reports', 'CP39 · EPF/SOCSO/EIS · EA 报表'),
    ('🏖️', 'Leave management',                  '请假管理'),
    ('📦', 'Inventory + purchase orders',       '库存 + 采购单'),
    ('📊', 'SST report + monthly filters',      'SST 报表 + 月份筛选'),
    ('💱', '17 currencies + live FX rates',     '17 种货币 + 实时汇率'),
    ('☁️', 'Cloud backup + Excel/JSON export',  '云端备份 + Excel/JSON 导出'),
  ];
}
