import 'dart:convert';

// ─── Transaction ──────────────────────────────────────────────────────────────
class Transaction {
  final int id;
  final String type;       // income | expense
  final String catId;
  final double amountMYR;
  final double origAmount;
  final String origCurrency;
  final String sstKey;
  final double sstMYR;
  final String descEN;
  final String descZH;
  final String date;       // yyyy-MM-dd
  final List<JournalEntry> entries;

  Transaction({
    required this.id,
    required this.type,
    required this.catId,
    required this.amountMYR,
    required this.origAmount,
    required this.origCurrency,
    required this.sstKey,
    required this.sstMYR,
    required this.descEN,
    required this.descZH,
    required this.date,
    required this.entries,
  });

  Transaction copyWith({
    int? id, String? type, String? catId,
    double? amountMYR, double? origAmount, String? origCurrency,
    String? sstKey, double? sstMYR,
    String? descEN, String? descZH, String? date,
    List<JournalEntry>? entries,
  }) => Transaction(
    id: id ?? this.id, type: type ?? this.type, catId: catId ?? this.catId,
    amountMYR: amountMYR ?? this.amountMYR, origAmount: origAmount ?? this.origAmount,
    origCurrency: origCurrency ?? this.origCurrency,
    sstKey: sstKey ?? this.sstKey, sstMYR: sstMYR ?? this.sstMYR,
    descEN: descEN ?? this.descEN, descZH: descZH ?? this.descZH,
    date: date ?? this.date, entries: entries ?? this.entries,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'type': type, 'cat_id': catId,
    'amount_myr': amountMYR, 'orig_amount': origAmount, 'orig_currency': origCurrency,
    'sst_key': sstKey, 'sst_myr': sstMYR,
    'desc_en': descEN, 'desc_zh': descZH, 'date': date,
    'entries': jsonEncode(entries.map((e) => e.toMap()).toList()),
  };

  factory Transaction.fromMap(Map<String, dynamic> m) {
    final entriesRaw = m['entries'];
    List<JournalEntry> entries = [];
    if (entriesRaw is String) {
      final list = jsonDecode(entriesRaw) as List;
      entries = list.map((e) => JournalEntry.fromMap(e)).toList();
    }
    return Transaction(
      id: m['id'] as int,
      type: m['type'] as String,
      catId: m['cat_id'] as String,
      amountMYR: (m['amount_myr'] as num).toDouble(),
      origAmount: (m['orig_amount'] as num).toDouble(),
      origCurrency: m['orig_currency'] as String,
      sstKey: m['sst_key'] as String,
      sstMYR: (m['sst_myr'] as num).toDouble(),
      descEN: m['desc_en'] as String,
      descZH: m['desc_zh'] as String,
      date: m['date'] as String,
      entries: entries,
    );
  }
}

class JournalEntry {
  final String acc;
  final String dc;
  final double val;
  JournalEntry({required this.acc, required this.dc, required this.val});
  Map<String, dynamic> toMap() => {'acc': acc, 'dc': dc, 'val': val};
  factory JournalEntry.fromMap(Map<String, dynamic> m) =>
    JournalEntry(acc: m['acc'], dc: m['dc'], val: (m['val'] as num).toDouble());
}

// ─── Customer ─────────────────────────────────────────────────────────────────
class Customer {
  final int id;
  final String name;
  final String regNo;
  final String sstRegNo;
  final String address;
  final String phone;
  final String email;

  Customer({
    required this.id,
    required this.name,
    this.regNo = '',
    this.sstRegNo = '',
    this.address = '',
    this.phone = '',
    this.email = '',
  });

  Customer copyWith({
    int? id, String? name, String? regNo, String? sstRegNo,
    String? address, String? phone, String? email,
  }) => Customer(
    id: id ?? this.id, name: name ?? this.name,
    regNo: regNo ?? this.regNo, sstRegNo: sstRegNo ?? this.sstRegNo,
    address: address ?? this.address, phone: phone ?? this.phone,
    email: email ?? this.email,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'reg_no': regNo, 'sst_reg_no': sstRegNo,
    'address': address, 'phone': phone, 'email': email,
  };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
    id: m['id'] as int, name: m['name'] as String,
    regNo: m['reg_no'] ?? '', sstRegNo: m['sst_reg_no'] ?? '',
    address: m['address'] ?? '', phone: m['phone'] ?? '', email: m['email'] ?? '',
  );
}

// ─── Employee ─────────────────────────────────────────────────────────────────
class Employee {
  final int id;
  final String name;
  final String icNo;
  final String position;
  final String department;
  final double basicSalary;
  final String epfNo;
  final String socsoNo;
  final String bankName;
  final String bankAcct;
  final String phone;
  final String email;

  Employee({
    required this.id,
    required this.name,
    this.icNo = '',
    this.position = '',
    this.department = '',
    this.basicSalary = 0,
    this.epfNo = '',
    this.socsoNo = '',
    this.bankName = '',
    this.bankAcct = '',
    this.phone = '',
    this.email = '',
  });

  Employee copyWith({
    int? id, String? name, String? icNo, String? position,
    String? department, double? basicSalary, String? epfNo,
    String? socsoNo, String? bankName, String? bankAcct,
    String? phone, String? email,
  }) => Employee(
    id: id ?? this.id, name: name ?? this.name,
    icNo: icNo ?? this.icNo, position: position ?? this.position,
    department: department ?? this.department,
    basicSalary: basicSalary ?? this.basicSalary,
    epfNo: epfNo ?? this.epfNo, socsoNo: socsoNo ?? this.socsoNo,
    bankName: bankName ?? this.bankName, bankAcct: bankAcct ?? this.bankAcct,
    phone: phone ?? this.phone, email: email ?? this.email,
  );

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'ic_no': icNo, 'position': position,
    'department': department, 'basic_salary': basicSalary,
    'epf_no': epfNo, 'socso_no': socsoNo,
    'bank_name': bankName, 'bank_acct': bankAcct,
    'phone': phone, 'email': email,
  };

  factory Employee.fromMap(Map<String, dynamic> m) => Employee(
    id: m['id'] as int, name: m['name'] as String,
    icNo: m['ic_no'] ?? '', position: m['position'] ?? '',
    department: m['department'] ?? '',
    basicSalary: (m['basic_salary'] as num?)?.toDouble() ?? 0,
    epfNo: m['epf_no'] ?? '', socsoNo: m['socso_no'] ?? '',
    bankName: m['bank_name'] ?? '', bankAcct: m['bank_acct'] ?? '',
    phone: m['phone'] ?? '', email: m['email'] ?? '',
  );
}

// ─── App Settings ─────────────────────────────────────────────────────────────
class AppSettings {
  final String lang;
  final String companyName;
  final String sstRegNo;
  final String coReg;
  final String coAddr;
  final String coPhone;
  final String coEmail;
  final String displayCurrency;

  const AppSettings({
    this.lang = 'en',
    this.companyName = '',
    this.sstRegNo = '',
    this.coReg = '',
    this.coAddr = '',
    this.coPhone = '',
    this.coEmail = '',
    this.displayCurrency = 'MYR',
  });

  AppSettings copyWith({
    String? lang, String? companyName, String? sstRegNo,
    String? coReg, String? coAddr, String? coPhone,
    String? coEmail, String? displayCurrency,
  }) => AppSettings(
    lang: lang ?? this.lang,
    companyName: companyName ?? this.companyName,
    sstRegNo: sstRegNo ?? this.sstRegNo,
    coReg: coReg ?? this.coReg,
    coAddr: coAddr ?? this.coAddr,
    coPhone: coPhone ?? this.coPhone,
    coEmail: coEmail ?? this.coEmail,
    displayCurrency: displayCurrency ?? this.displayCurrency,
  );

  Map<String, dynamic> toMap() => {
    'lang': lang, 'company_name': companyName, 'sst_reg_no': sstRegNo,
    'co_reg': coReg, 'co_addr': coAddr, 'co_phone': coPhone,
    'co_email': coEmail, 'display_currency': displayCurrency,
  };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
    lang: m['lang'] ?? 'en',
    companyName: m['company_name'] ?? '',
    sstRegNo: m['sst_reg_no'] ?? '',
    coReg: m['co_reg'] ?? '',
    coAddr: m['co_addr'] ?? '',
    coPhone: m['co_phone'] ?? '',
    coEmail: m['co_email'] ?? '',
    displayCurrency: m['display_currency'] ?? 'MYR',
  );
}
