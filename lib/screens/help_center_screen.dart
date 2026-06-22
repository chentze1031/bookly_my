import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';

// In-app Help Center — categorised, expandable FAQ in EN / 中文 / BM.
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  // (icon, section title, [ (question, answer) ... ])
  static List<(String, String, List<(String, String)>)> _sections(String l) => [
    ('🚀', tr(l, 'Getting Started', '入门', 'Mula'), [
      (
        tr(l, 'How do I add income or an expense?', '怎么添加收入 / 支出?', 'Bagaimana tambah pendapatan / belanja?'),
        tr(l,
          'On the Home tab, tap "Add Income" or "Add Expense", pick a category, enter the amount, and save.',
          '在首页点「添加收入」或「添加支出」,选分类、填金额、保存即可。',
          'Di Laman Utama, ketik "Tambah Pendapatan" atau "Tambah Belanja", pilih kategori, masukkan jumlah, dan simpan.'),
      ),
      (
        tr(l, 'How do I sign in and sync?', '如何登录并同步?', 'Bagaimana log masuk & segerak?'),
        tr(l,
          'Go to Settings → Account → Sign in with Google. Your data then syncs to the cloud and across devices. You can also use the app offline as a guest.',
          '设置 → 账户 → 用 Google 登录。之后数据会同步到云端、多设备共用。也可以离线以访客身份使用。',
          'Tetapan → Akaun → Log masuk dengan Google. Data anda disegerakkan ke awan & merentas peranti. Anda juga boleh guna luar talian sebagai tetamu.'),
      ),
      (
        tr(l, 'Change language or dark mode?', '切换语言 / 深色模式?', 'Tukar bahasa / mod gelap?'),
        tr(l,
          'Settings → Language (EN / 中文 / BM) and Settings → Theme (Dark mode).',
          '设置 → 语言(EN / 中文 / BM);设置 → 主题(深色模式)。',
          'Tetapan → Bahasa (EN / 中文 / BM); Tetapan → Tema (Mod Gelap).'),
      ),
    ]),
    ('🧾', tr(l, 'Invoices & Documents', '发票与单据', 'Invois & Dokumen'), [
      (
        tr(l, 'How do I create an invoice?', '如何开发票?', 'Bagaimana cipta invois?'),
        tr(l,
          'Home → Invoice → fill in customer, items and tax → Save → Share/Export PDF. Add your logo & signature in Settings → Company info.',
          '首页 → 发票 → 填客户、项目、税 → 保存 → 分享 / 导出 PDF。logo 与签名在 设置 → 公司资料 里设置。',
          'Laman Utama → Invois → isi pelanggan, item & cukai → Simpan → Kongsi/Eksport PDF. Tambah logo & tandatangan di Tetapan → Maklumat syarikat.'),
      ),
      (
        tr(l, 'Quotation, delivery order, bill, credit note, PO?', '报价单 / 送货单 / 账单 / 信用备注 / 采购单?', 'Sebut harga / nota penghantaran / bil / nota kredit / PO?'),
        tr(l,
          'Quotation and Bill are quick buttons on Home; Delivery Orders and Credit Notes are in the Home record shortcuts (each with its own history list). Purchase Orders live under the Inventory tab.',
          '报价单、账单是首页的快捷按钮;送货单、信用备注在首页的记录入口(各有自己的列表)。采购单在「库存」标签里。',
          'Sebut harga & Bil ialah butang pantas di Laman Utama; Nota Penghantaran & Nota Kredit di pintasan rekod Laman Utama. Pesanan Belian (PO) di bawah tab Inventori.'),
      ),
    ]),
    ('📦', tr(l, 'Inventory', '库存', 'Inventori'), [
      (
        tr(l, 'How do I manage stock?', '如何管理库存?', 'Bagaimana urus stok?'),
        tr(l,
          'Open the Inventory tab to add items (name, cost, price, quantity, barcode/photo). Stock is deducted automatically when you sell those items on an invoice. Adding product photos is a Pro feature.',
          '打开「库存」标签,添加商品(名称、成本、售价、数量、条码 / 图片)。开发票售出这些商品时,库存自动扣减。加产品图片是 Pro 功能。',
          'Buka tab Inventori untuk tambah item (nama, kos, harga, kuantiti, kod bar/foto). Stok ditolak automatik bila anda jual item itu pada invois. Foto produk ialah ciri Pro.'),
      ),
    ]),
    ('💼', tr(l, 'Payroll', '薪资', 'Gaji'), [
      (
        tr(l, 'How do I generate a payslip?', '如何生成工资单?', 'Bagaimana jana slip gaji?'),
        tr(l,
          'Home → Payslip → pick the employee, enter earnings/deductions, toggle EPF/SOCSO/EIS/PCB → Save. View saved ones under Payroll History.',
          '首页 → 薪资 → 选员工、填收入 / 扣款、勾选 EPF/SOCSO/EIS/PCB → 保存。已存的在「薪资记录」里看。',
          'Laman Utama → Slip Gaji → pilih pekerja, isi pendapatan/potongan, hidupkan EPF/SOCSO/EIS/PCB → Simpan. Lihat di Sejarah Gaji.'),
      ),
      (
        tr(l, 'How are EPF / SOCSO / EIS / PCB calculated?', 'EPF / SOCSO / EIS / PCB 怎么算?', 'Bagaimana EPF / SOCSO / EIS / PCB dikira?'),
        tr(l,
          'EPF: employee 11%, employer 13% (≤RM5,000) or 12%. SOCSO & EIS use the PERKESO wage-band table (RM6,000 ceiling). PCB is an estimate from the LHDN tax schedule. Verify against official tables before filing.',
          'EPF:员工 11%、雇主 13%(≤RM5,000)或 12%。SOCSO 与 EIS 按 PERKESO 工资段表(RM6,000 上限)。PCB 按 LHDN 税率表估算。正式报税前请对照官方表核对。',
          'EPF: pekerja 11%, majikan 13% (≤RM5,000) atau 12%. SOCSO & EIS guna jadual band gaji PERKESO (siling RM6,000). PCB ialah anggaran dari jadual cukai LHDN. Sahkan dengan jadual rasmi sebelum failkan.'),
      ),
      (
        tr(l, 'Does payroll post to my accounts?', '薪资会入账吗?', 'Adakah gaji masuk ke akaun?'),
        tr(l,
          'Yes. Saving a payslip posts a double-entry journal (salary + employer statutory as expenses, payables as liabilities). Mark it "Paid" in Payroll History to clear the payables to bank.',
          '会。保存工资单会过一笔复式日记账(税前薪资 + 雇主缴款记为费用,应付记为负债)。在「薪资记录」标记「已支付」后,应付会冲销到银行。',
          'Ya. Menyimpan slip gaji mencatat jurnal catatan-bergu (gaji + statutori majikan sebagai belanja, akaun belum bayar sebagai liabiliti). Tanda "Dibayar" di Sejarah Gaji untuk selesaikan ke bank.'),
      ),
    ]),
    ('🏛️', tr(l, 'Tax & MyInvois', '税务与 MyInvois', 'Cukai & MyInvois'), [
      (
        tr(l, 'How do I set SST on invoices?', '发票怎么设 SST?', 'Bagaimana tetapkan SST pada invois?'),
        tr(l,
          'Each invoice line lets you choose the SST rate (Sales 5%/10% or Service 6%/8%). Reports → SST-02 summarises taxable sales and SST by rate for filing.',
          '每个发票行都能选 SST 税率(销售 5%/10% 或服务 6%/8%)。报表 → SST-02 按税率汇总应税销售与 SST,便于申报。',
          'Setiap baris invois boleh pilih kadar SST (Jualan 5%/10% atau Servis 6%/8%). Laporan → SST-02 meringkaskan jualan bercukai & SST mengikut kadar.'),
      ),
      (
        tr(l, 'How do I submit a MyInvois e-Invoice?', '怎么提交 MyInvois 电子发票?', 'Bagaimana hantar e-Invois MyInvois?'),
        tr(l,
          'Configure your MyInvois client ID/secret in Settings → MyInvois (Pro). Open an invoice → submit. Track status, cancel within 72h, and view the QR under Home → MyInvois Records.',
          '在 设置 → MyInvois(Pro)里配置 client ID/secret。打开发票 → 提交。状态、72 小时内取消、验证 QR 都在 首页 → MyInvois 记录 里。',
          'Konfigur client ID/secret MyInvois di Tetapan → MyInvois (Pro). Buka invois → hantar. Jejak status, batal dalam 72 jam, lihat QR di Laman Utama → Rekod MyInvois.'),
      ),
      (
        tr(l, 'Test Mode vs Live Mode?', '测试模式 vs 正式模式?', 'Mod Ujian vs Mod Sebenar?'),
        tr(l,
          'Test Mode (sandbox) is for trying things out — data has no legal effect and is NOT sent to LHDN. Live Mode really submits to LHDN. Switch in Settings → MyInvois.',
          '测试模式(沙盒)用来试功能——数据无法律效力、不会提交给税局。正式模式才真正提交 LHDN。在 设置 → MyInvois 切换。',
          'Mod Ujian (sandbox) untuk mencuba — data tiada kesan undang-undang & TIDAK dihantar ke LHDN. Mod Sebenar benar-benar hantar ke LHDN. Tukar di Tetapan → MyInvois.'),
      ),
      (
        tr(l, 'Consolidated (B2C) and self-billed e-Invoice?', '合并发票 (B2C) 与自开发票?', 'e-Invois disatukan (B2C) & layan diri?'),
        tr(l,
          'Consolidated: batch all walk-in (no-TIN) sales into one monthly e-Invoice (Settings → MyInvois). Self-billed: you issue on a supplier\'s behalf (e.g. foreign suppliers).',
          '合并发票:把当月所有散客(无 TIN)销售汇总成一张电子发票(设置 → MyInvois)。自开发票:由你代供应商开具(如外国供应商)。',
          'Disatukan: kumpul semua jualan pejalan kaki (tanpa TIN) jadi satu e-Invois bulanan (Tetapan → MyInvois). Layan diri: anda keluarkan bagi pihak pembekal (cth. pembekal asing).'),
      ),
      (
        tr(l, 'How does a customer get their e-Invoice?', '顾客怎么拿到自己的 e-Invoice?', 'Bagaimana pelanggan dapat e-Invois mereka?'),
        tr(l,
          'Enter the customer\'s TIN on the invoice before submitting — MyInvois then files it under their TIN automatically, and it appears in their own MyInvois account.',
          '提交前在发票上填顾客的 TIN——系统会按 TIN 自动归属,发票就会出现在顾客自己的 MyInvois 账户里。',
          'Masukkan TIN pelanggan pada invois sebelum hantar — MyInvois akan failkan di bawah TIN mereka, dan ia muncul dalam akaun MyInvois mereka.'),
      ),
    ]),
    ('📊', tr(l, 'Reports & Accounting', '报表与账务', 'Laporan & Perakaunan'), [
      (
        tr(l, 'What do the reports show?', '报表看什么?', 'Apa yang laporan tunjuk?'),
        tr(l,
          'Reports tab: Profit & Loss and Balance Sheet. Accounting tab: Receivables, Payables, Trial Balance and General Ledger. All can be exported to PDF (Pro).',
          '「报表」标签:损益表、资产负债表。「账务」标签:应收、应付、试算表、总账。都可导出 PDF(Pro)。',
          'Tab Laporan: Untung Rugi & Kunci Kira-kira. Tab Perakaunan: Belum Terima, Belum Bayar, Imbangan Duga & Lejar Am. Semua boleh eksport PDF (Pro).'),
      ),
    ]),
    ('✨', tr(l, 'Pro, AI & Extras', 'Pro、AI 与其他', 'Pro, AI & Lain'), [
      (
        tr(l, 'What does Bookly Pro include?', 'Bookly Pro 有什么?', 'Apa yang Bookly Pro ada?'),
        tr(l,
          'Pro removes ads and unlocks multiple company ledgers, recurring transactions, MyInvois e-Invoice, document exports, receipt scanning and more. Subscribe via Settings → Bookly PRO.',
          'Pro 去广告,并解锁多公司账本、定期记账、MyInvois 电子发票、单据导出、拍照收据等。在 设置 → Bookly PRO 订阅。',
          'Pro buang iklan & buka lejar pelbagai syarikat, transaksi berulang, e-Invois MyInvois, eksport dokumen, imbas resit dll. Langgan di Tetapan → Bookly PRO.'),
      ),
      (
        tr(l, 'How does scan receipt work?', '拍照收据怎么用?', 'Bagaimana imbas resit berfungsi?'),
        tr(l,
          'Home → Add Expense → "Scan receipt" (Pro). Snap the receipt and AI fills in the merchant, amount, date and category for you to confirm.',
          '首页 → 添加支出 → 「扫描收据」(Pro)。拍一下收据,AI 自动填好商家、金额、日期、分类,你确认即可。',
          'Laman Utama → Tambah Belanja → "Imbas resit" (Pro). Ambil gambar resit dan AI isi peniaga, jumlah, tarikh & kategori untuk anda sahkan.'),
      ),
      (
        tr(l, 'Multiple companies?', '多公司账本?', 'Pelbagai syarikat?'),
        tr(l,
          'Settings → Company → Add company (Pro). Each company keeps its own books; tap to switch. The active company\'s data is separate from the others.',
          '设置 → 公司 → 添加公司(Pro)。每家公司独立记账,点击切换。当前公司的数据与其他公司分开。',
          'Tetapan → Syarikat → Tambah syarikat (Pro). Setiap syarikat ada buku sendiri; ketik untuk tukar. Data syarikat aktif berasingan.'),
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final sections = _sections(lang);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Help Center', '帮助中心', 'Pusat Bantuan')),
        backgroundColor: kSurface, foregroundColor: kText, elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          for (final s in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
              child: Text('${s.$1}  ${s.$2}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
            ),
            Container(
              decoration: BoxDecoration(
                color: kSurface, border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                for (int i = 0; i < s.$3.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: kBorder),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      iconColor: kMuted, collapsedIconColor: kMuted,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      expandedAlignment: Alignment.centerLeft,
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      title: Text(s.$3[i].$1,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText)),
                      children: [
                        Text(s.$3[i].$2,
                          style: const TextStyle(fontSize: 13, color: kMuted, height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ]),
            ),
          ],
          const SizedBox(height: 18),
          // Contact support
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface, border: Border.all(color: kBorder),
              borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✉️  ${tr(lang, 'Still need help?', '还需要帮助?', 'Masih perlu bantuan?')}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 6),
              Text(tr(lang,
                'Email us and we\'ll get back to you:',
                '发邮件给我们,会尽快回复:',
                'E-mel kami dan kami akan balas:'),
                style: const TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 4),
              SelectableText('bookly.malaysia@gmail.com',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kBlue)),
            ]),
          ),
        ],
      ),
    );
  }
}
