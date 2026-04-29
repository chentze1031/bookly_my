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

final incomeCategories = <TxCategory>[
  TxCategory(id:'product_sale', icon:'📦', color:kGreen,           enLabel:'Product Sale',      zhLabel:'产品销售',   type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4010',dc:'Cr',val:a)]),
  TxCategory(id:'service_sale', icon:'🛠', color:Color(0xFF059669), enLabel:'Service',           zhLabel:'服务/咨询',  type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4020',dc:'Cr',val:a)]),
  TxCategory(id:'invoice_paid', icon:'🧾', color:Color(0xFF0D9488), enLabel:'Invoice Collected', zhLabel:'收款',      type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4010',dc:'Cr',val:a)]),
  TxCategory(id:'other_income', icon:'💰', color:Color(0xFF0891B2), enLabel:'Other Income',      zhLabel:'其他收入',   type:'income', mkEntries:(a)=>[JournalEntry(acc:'1020',dc:'Dr',val:a),JournalEntry(acc:'4030',dc:'Cr',val:a)]),
];

final expenseCategories = <TxCategory>[
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

// ─── i18n ─────────────────────────────────────────────────────────────────────
class L10n {
  final String lang;
  const L10n(this.lang);

  bool get isZh => lang == 'zh';

  // Navigation
  String get appName    => isZh ? '账本 MY' : 'Bookly MY';
  String get home       => isZh ? '首页' : 'Home';
  String get records    => isZh ? '记录' : 'Records';
  String get reports    => isZh ? '报表' : 'Reports';
  String get settings   => isZh ? '设置' : 'Settings';

  // Home
  String get netProfit  => isZh ? '净利润' : 'Net Profit';
  String get income     => isZh ? '收入' : 'Income';
  String get expenses   => isZh ? '支出' : 'Expenses';
  String get addIncome  => isZh ? '添加收入' : 'Add Income';
  String get addExpense => isZh ? '添加支出' : 'Add Expense';
  String get topSpend   => isZh ? '主要支出' : 'Top Spending';
  String get recent     => isZh ? '最近记录' : 'Recent';

  // List/filter
  String get all        => isZh ? '全部' : 'All';
  String get noTx       => isZh ? '暂无记录' : 'No transactions';
  String get search     => isZh ? '搜索…' : 'Search…';
  String get allTime    => isZh ? '全部时间' : 'All time';

  // Reports
  String get pl         => isZh ? '损益表' : 'Profit & Loss';
  String get bs         => isZh ? '资产负债表' : 'Balance Sheet';
  String get sstRep     => isZh ? 'SST 报告' : 'SST Report';
  String get revenue    => isZh ? '收入' : 'Revenue';
  String get cogs       => isZh ? '商品成本' : 'Cost of Goods';
  String get grossP     => isZh ? '毛利润' : 'Gross Profit';
  String get opex       => isZh ? '运营费用' : 'Operating Expenses';
  String get totalEx    => isZh ? '总支出' : 'Total Expenses';
  String get totalRev   => isZh ? '总收入' : 'Total Revenue';
  String get assets     => isZh ? '资产' : 'Assets';
  String get liab       => isZh ? '负债' : 'Liabilities';
  String get equity     => isZh ? '净资产' : 'Net Worth';
  String get cashBank   => isZh ? '银行存款' : 'Cash in Bank';
  String get ar         => isZh ? '应收账款' : 'Accounts Receivable';
  String get inventory  => isZh ? '库存' : 'Inventory';
  String get ap         => isZh ? '应付账款' : 'Accounts Payable';

  // SST report
  String get sstCollected => isZh ? '已收 SST' : 'SST Collected';
  String get sstPaid      => isZh ? '已付 SST' : 'SST Paid';
  String get sstNet       => isZh ? '净 SST' : 'Net SST';

  // Add Tx form
  String get moneyIn    => isZh ? '收款' : 'Money In';
  String get moneyOut   => isZh ? '付款' : 'Money Out';
  String get description=> isZh ? '备注（可选）' : 'Description (optional)';
  String get date       => isZh ? '日期' : 'Date';
  String get currency   => isZh ? '货币' : 'Currency';
  String get sstLabel   => isZh ? 'SST / 税率' : 'SST / Tax';
  String get back       => isZh ? '返回' : 'Back';
  String get change     => isZh ? '更改' : 'Change';
  String get save       => isZh ? '保存' : 'Save';
  String get edit       => isZh ? '编辑记录' : 'Edit Transaction';
  String get newTx      => isZh ? '新增记录' : 'New Transaction';
  String get autoLbl    => isZh ? '自动计入账目' : 'Auto-recorded as';
  String get fxRate     => isZh ? '汇率' : 'Rate';
  String get del        => isZh ? '删除' : 'Delete';
  String get keep       => isZh ? '保留' : 'Keep';

  // FX
  String get fxLive     => isZh ? '实时汇率' : 'Live rates';
  String get fxReset    => isZh ? '恢复默认' : 'Reset to defaults';

  // Settings
  String get settTitle  => isZh ? '设置' : 'Settings';
  String get coName     => isZh ? '公司名称' : 'Company Name';
  String get coReg      => isZh ? '公司注册号' : 'Company Reg No.';
  String get sstReg     => isZh ? 'SST 注册号' : 'SST Reg. No.';
  String get coAddr     => isZh ? '地址' : 'Address';
  String get coPhone    => isZh ? '电话' : 'Phone';
  String get coEmail    => isZh ? '邮箱' : 'Email';
  String get langLabel  => isZh ? '语言' : 'Language';

  // Cloud
  String get cloudSync  => isZh ? '云端同步' : 'Cloud Sync';
  String get cloudPull  => isZh ? '从云端加载' : 'Pull from cloud';
  String get cloudPush  => isZh ? '推送到云端' : 'Push to cloud';
  String get syncing    => isZh ? '同步中…' : 'Syncing…';
  String get export     => isZh ? '导出' : 'Export';
  String get xlsExport  => isZh ? '导出 Excel' : 'Export Excel';
  String get bakJson    => isZh ? '导出 JSON 备份' : 'Export JSON Backup';
  String get restJson   => isZh ? '从 JSON 恢复' : 'Restore from JSON';

  // Invoice
  String get invoice    => isZh ? '发票管理' : 'Invoice Manager';
  String get invNo      => isZh ? '发票号码' : 'Invoice No.';
  String get invDate    => isZh ? '发票日期' : 'Invoice Date';
  String get dueDate    => isZh ? '到期日' : 'Due Date';
  String get billTo     => isZh ? '客户' : 'Bill To';
  String get subTotal   => isZh ? '小计' : 'Subtotal';
  String get grandTotal => isZh ? '总计' : 'TOTAL DUE';
  String get bankName   => isZh ? '银行' : 'Bank Name';
  String get bankAcct   => isZh ? '账号' : 'Account No.';
  String get notes      => isZh ? '备注' : 'Notes';
  String get terms      => isZh ? '条款' : 'Terms & Conditions';
  String get sharePrint => isZh ? '分享 / 打印' : 'Share / Print';
  String get logo       => isZh ? '公司 Logo' : 'Company Logo';
  String get sig        => isZh ? '电子签名' : 'E-Signature';
  String get drawSig    => isZh ? '手写签名' : 'Draw';
  String get clearSig   => isZh ? '清除' : 'Clear';
  String get saveSig    => isZh ? '保存签名' : 'Save Signature';

  // Customer
  String get customers  => isZh ? '客户管理' : 'Customers';
  String get newCust    => isZh ? '新增客户' : 'New Customer';
  String get custName   => isZh ? '公司 / 名称' : 'Company / Name';
  String get custReg    => isZh ? '注册号' : 'Reg No.';
  String get custSST    => isZh ? 'SST 注册号' : 'SST Reg No.';
  String get custAddr   => isZh ? '地址' : 'Address';
  String get custPhone  => isZh ? '电话' : 'Phone';
  String get custEmail  => isZh ? '邮箱' : 'Email';

  // Employee
  String get employees  => isZh ? '员工管理' : 'Employees';
  String get newEmp     => isZh ? '新增员工' : 'Add Employee';
  String get empName    => isZh ? '姓名' : 'Full Name';
  String get empIC      => isZh ? 'IC 号码' : 'IC No.';
  String get empPos     => isZh ? '职位' : 'Position';
  String get empDept    => isZh ? '部门' : 'Department';
  String get empBasic   => isZh ? '基本薪资 (MYR)' : 'Basic Salary (MYR)';
  String get empEPF     => 'EPF No.';
  String get empSOCSO   => 'SOCSO No.';
  String get empBank    => isZh ? '银行' : 'Bank';
  String get empAcct    => isZh ? '账号' : 'Account No.';

  // Payroll
  String get payroll    => isZh ? '薪资管理' : 'Payroll';
  String get payEmp     => isZh ? '员工' : 'Employee';
  String get selEmp     => isZh ? '选择员工' : 'Select Employee';
  String get payPeriod  => isZh ? '薪资期间' : 'Pay Period';
  String get earnings   => isZh ? '收入项目' : 'Earnings';
  String get statutory  => isZh ? '法定缴款' : 'Statutory';
  String get otherDed   => isZh ? '其他扣款' : 'Other Deductions';
  String get grossPay   => isZh ? '总薪资' : 'Gross Pay';
  String get netPay     => isZh ? '实发薪资' : 'Net Pay';
  String get totalDed   => isZh ? '总扣款' : 'Total Deductions';
  String get totalCost  => isZh ? '雇主总成本' : 'Total Employer Cost';

  // Subscription
  String get proTitle   => 'Bookly PRO';
  String get proSub     => isZh ? '解锁所有高级功能' : 'Unlock all features';
  String get monthly    => isZh ? '按月订阅' : 'Monthly';
  String get yearly     => isZh ? '按年订阅' : 'Yearly';
  String get mPrice     => 'RM 9.90 / ${isZh ? "月" : "month"}';
  String get yPrice     => 'RM 49.90 / ${isZh ? "年" : "year"}';
  String get ySave      => isZh ? '省58%' : 'Save 58%';
  String get subM       => isZh ? '月订阅 – RM 9.90' : 'Subscribe Monthly – RM 9.90';
  String get subY       => isZh ? '年订阅 – RM 49.90' : 'Subscribe Yearly – RM 49.90';
  String get restore    => isZh ? '恢复购买' : 'Restore Purchases';
  String get watchAd    => isZh ? '看广告' : 'Watch Ad';
  String get adPass     => isZh ? '免费日通行证' : 'Free Day Pass';
  String get adDesc     => isZh ? '观看3个广告，解锁24小时' : 'Watch 3 ads to unlock 24 hours';
  String get proLocked  => isZh ? 'Pro 专属功能' : 'Pro Feature';
  String get proUnlock  => isZh ? '升级 Pro 解锁' : 'Upgrade to unlock';
  String get freePlan   => isZh ? '免费版' : 'Free Plan';
  String get proExpires => isZh ? '到期时间' : 'Expires';
  String get manageSub  => isZh ? '管理订阅' : 'Manage Subscription';
  String get dayActive  => isZh ? '📺 日通行证有效至' : '📺 Day Pass active until';

  // Misc
  String get reminder   => isZh
    ? 'SST 门槛：年营业额 RM50万 · 超 RM100万须电子发票'
    : 'SST threshold: RM 500k/year · e-Invoice above RM 1M';

  static const features = [
    ('♾️', 'Unlimited transactions',           '无限记录笔数'),
    ('💱', '17 currencies + live FX rates',    '17种货币 + 实时汇率'),
    ('✏️', 'Edit & search transactions',       '编辑和搜索记录'),
    ('📊', 'SST report + monthly filters',     'SST报表 + 月份筛选'),
    ('🧾', 'Malaysia Tax Invoice + signature', '马来西亚税务发票 + 签名'),
    ('💼', 'Payroll + payslip generator',      '薪资单生成器'),
    ('👥', 'Customer & employee database',     '客户和员工数据库'),
    ('🇲🇾', 'EPF / SOCSO / EIS calculator',   'EPF/SOCSO/EIS 计算'),
    ('☁️', 'Cloud backup (Supabase)',          '云端备份'),
    ('📥', 'Excel & JSON export',              'Excel / JSON 导出'),
  ];
}
