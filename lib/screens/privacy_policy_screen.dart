import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/app_state.dart';

// ════════════════════════════════════════════════════════════════════════════
// PRIVACY POLICY / PDPA  — in-app full text, trilingual (EN / 中文 / BM)
// Reachable from Settings → Privacy and from the auth screen footer link.
// Informational only: no consent gate / checkbox is required to use the app.
// ════════════════════════════════════════════════════════════════════════════
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // (emoji, section heading, body) tuples — translated inline via tr().
  static List<(String, String, String)> _sections(String l) => [
    (
      '🛡️',
      tr(l, 'Our commitment', '我们的承诺', 'Komitmen kami'),
      tr(l,
        'Bookly MY ("we", "the app") respects your privacy and handles your personal data in line with Malaysia\'s Personal Data Protection Act 2010 (PDPA). This policy explains what we collect, why, and the choices you have.',
        'Bookly MY（「我们」、「本应用」）尊重您的隐私，并依据马来西亚《2010 年个人资料保护法令》（PDPA）处理您的个人资料。本政策说明我们收集哪些资料、用途，以及您拥有的选择。',
        'Bookly MY ("kami", "aplikasi ini") menghormati privasi anda dan mengendalikan data peribadi anda selaras dengan Akta Perlindungan Data Peribadi 2010 (PDPA) Malaysia. Dasar ini menerangkan apa yang kami kumpul, sebabnya, dan pilihan yang anda ada.'),
    ),
    (
      '📋',
      tr(l, 'What we collect', '我们收集什么', 'Apa yang kami kumpul'),
      tr(l,
        '• Account info: your name and email when you sign in with Google.\n'
        '• Business records you enter: transactions, customers, suppliers, employees, invoices and inventory.\n'
        '• Device & usage data needed to run the app (e.g. app settings, anonymous diagnostics).\n'
        'We do NOT collect your Google password, and we do not ask for IC numbers or bank login credentials.',
        '• 账户资料：当您使用 Google 登录时的姓名和电邮。\n'
        '• 您输入的业务记录：交易、客户、供应商、员工、发票和库存。\n'
        '• 运行应用所需的设备与使用数据（例如应用设置、匿名诊断信息）。\n'
        '我们「不」收集您的 Google 密码，也不会索取身份证号码或银行登录凭证。',
        '• Maklumat akaun: nama dan emel anda apabila log masuk dengan Google.\n'
        '• Rekod perniagaan yang anda masukkan: transaksi, pelanggan, pembekal, pekerja, invois dan inventori.\n'
        '• Data peranti & penggunaan yang diperlukan untuk menjalankan aplikasi (cth. tetapan aplikasi, diagnostik tanpa nama).\n'
        'Kami TIDAK mengumpul kata laluan Google anda, dan tidak meminta nombor IC atau maklumat log masuk bank.'),
    ),
    (
      '🎯',
      tr(l, 'How we use your data', '我们如何使用您的资料', 'Bagaimana kami guna data anda'),
      tr(l,
        'We use your data only to provide and improve the app: to store and sync your books, generate invoices and reports, support e-Invoice (MyInvois) submission, and keep your account secure. We do not sell your personal data to anyone.',
        '我们仅将您的资料用于提供和改进应用：保存与同步您的账目、生成发票和报表、支持 e-Invoice（MyInvois）提交，以及保护您的账户安全。我们不会向任何人出售您的个人资料。',
        'Kami menggunakan data anda hanya untuk menyediakan dan menambah baik aplikasi: menyimpan dan menyegerak buku anda, menjana invois dan laporan, menyokong penghantaran e-Invois (MyInvois), serta memastikan akaun anda selamat. Kami tidak menjual data peribadi anda kepada sesiapa.'),
    ),
    (
      '☁️',
      tr(l, 'Storage & cloud sync', '存储与云端同步', 'Penyimpanan & segerak awan'),
      tr(l,
        'Your records are stored on your device. If you sign in, an encrypted copy is synced to our cloud (Supabase) so you can use multiple devices and restore after reinstalling. As a guest, your data stays only on your device. You can export a full backup at any time from Settings → Backup.',
        '您的记录保存在本设备上。若您登录，会有一份加密副本同步到我们的云端（Supabase），以便您多设备使用并在重装后恢复。以访客身份使用时，数据仅保留在本设备。您可随时在 设置 → 备份 中导出完整备份。',
        'Rekod anda disimpan pada peranti anda. Jika anda log masuk, salinan tersulit disegerakkan ke awan kami (Supabase) supaya anda boleh guna pelbagai peranti dan pulih selepas pasang semula. Sebagai tetamu, data anda kekal pada peranti anda sahaja. Anda boleh eksport sandaran penuh bila-bila masa di Tetapan → Sandaran.'),
    ),
    (
      '🤝',
      tr(l, 'Third-party services', '第三方服务', 'Perkhidmatan pihak ketiga'),
      tr(l,
        'We rely on trusted providers that process limited data on our behalf:\n'
        '• Google Sign-In — authentication.\n'
        '• Supabase — secure cloud storage & sync.\n'
        '• RevenueCat / Google Play — subscription billing for Pro.\n'
        '• Google AdMob — ads shown in the free version.\n'
        '• LHDN MyInvois — only the invoice data you choose to submit.\n'
        'Each provider has its own privacy policy.',
        '我们依赖可信的服务商代表我们处理有限的数据：\n'
        '• Google 登录 — 身份验证。\n'
        '• Supabase — 安全的云端存储与同步。\n'
        '• RevenueCat / Google Play — Pro 订阅计费。\n'
        '• Google AdMob — 免费版中展示的广告。\n'
        '• LHDN MyInvois — 仅限您选择提交的发票数据。\n'
        '每家服务商均有各自的隐私政策。',
        'Kami bergantung pada penyedia dipercayai yang memproses data terhad bagi pihak kami:\n'
        '• Google Sign-In — pengesahan.\n'
        '• Supabase — penyimpanan & segerak awan yang selamat.\n'
        '• RevenueCat / Google Play — pengebilan langganan Pro.\n'
        '• Google AdMob — iklan dalam versi percuma.\n'
        '• LHDN MyInvois — hanya data invois yang anda pilih untuk hantar.\n'
        'Setiap penyedia mempunyai dasar privasi masing-masing.'),
    ),
    (
      '⚖️',
      tr(l, 'Your rights (PDPA)', '您的权利（PDPA）', 'Hak anda (PDPA)'),
      tr(l,
        'Under the PDPA you may access and correct your personal data, withdraw consent, and ask us to delete your account and associated data. You can edit or delete your records in the app directly, or contact us to remove your account entirely.',
        '根据 PDPA，您有权查阅和更正您的个人资料、撤回同意，并要求我们删除您的账户及相关数据。您可直接在应用内编辑或删除记录，或联系我们以完全删除账户。',
        'Di bawah PDPA, anda boleh mengakses dan membetulkan data peribadi anda, menarik balik persetujuan, dan meminta kami memadam akaun serta data berkaitan. Anda boleh edit atau padam rekod dalam aplikasi terus, atau hubungi kami untuk memadam akaun sepenuhnya.'),
    ),
    (
      '🗄️',
      tr(l, 'Retention & security', '保留与安全', 'Pengekalan & keselamatan'),
      tr(l,
        'We keep your data for as long as your account is active. Cloud data is protected with encryption in transit and access controls. If you delete your account, we remove your synced data from our servers. Records kept only on your device are erased when you uninstall the app.',
        '只要您的账户处于活跃状态，我们就会保留您的数据。云端数据采用传输加密和访问控制保护。若您删除账户，我们会从服务器移除您的同步数据。仅保存在本设备的记录会在您卸载应用时被清除。',
        'Kami menyimpan data anda selagi akaun anda aktif. Data awan dilindungi dengan penyulitan semasa penghantaran dan kawalan akses. Jika anda padam akaun, kami buang data tersegerak anda dari pelayan kami. Rekod yang disimpan pada peranti sahaja akan dipadam apabila anda nyahpasang aplikasi.'),
    ),
    (
      '✉️',
      tr(l, 'Contact us', '联系我们', 'Hubungi kami'),
      tr(l,
        'Questions about this policy or your data? Email us at chentze961031@gmail.com and we\'ll respond as soon as we can.',
        '对本政策或您的数据有疑问？请电邮至 chentze961031@gmail.com，我们会尽快回复。',
        'Soalan tentang dasar ini atau data anda? Emel kami di chentze961031@gmail.com dan kami akan balas secepat mungkin.'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppState>().settings.lang;
    final sections = _sections(lang);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(lang, 'Privacy Policy', '隐私政策', 'Dasar Privasi')),
        backgroundColor: kSurface,
        foregroundColor: kText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kBlueBg,
              border: Border.all(color: kBlueBd),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              tr(lang,
                'Privacy Policy & PDPA notice · Last updated: June 2026',
                '隐私政策与 PDPA 声明 · 最近更新：2026 年 6 月',
                'Dasar Privasi & notis PDPA · Kemas kini terakhir: Jun 2026'),
              style: TextStyle(color: kText, fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          for (final s in sections) _section(s.$1, s.$2, s.$3),
        ],
      ),
    );
  }

  Widget _section(String emoji, String title, String body) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kSurface,
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kText)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(color: kText, fontSize: 13, height: 1.5)),
      ],
    ),
  );
}
