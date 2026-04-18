import 'package:flutter/material.dart';
import '../constants.dart';

// ─── Pro Badge ────────────────────────────────────────────────────────────────
class ProBadge extends StatelessWidget {
  final bool small;
  const ProBadge({super.key, this.small = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 9, vertical: small ? 2 : 3),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFA855F7)]),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text('✦ PRO',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800,
        fontSize: small ? 9 : 11, letterSpacing: 0.5)),
  );
}

// ─── Section Card ─────────────────────────────────────────────────────────────
class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const SectionCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    decoration: BoxDecoration(
      color: kSurface,
      border: Border.all(color: kBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: const BoxDecoration(
            color: kBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: kBorder)),
          ),
          width: double.infinity,
          child: Text(title,
            style: const TextStyle(color: kMuted, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.6),),
        ),
        child,
      ],
    ),
  );
}

// ─── Lock Banner ─────────────────────────────────────────────────────────────
class LockBanner extends StatelessWidget {
  final VoidCallback onUpgrade;
  final String label;
  final String sublabel;
  const LockBanner({super.key, required this.onUpgrade,
    this.label = 'Pro Feature', this.sublabel = 'Upgrade to unlock'});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onUpgrade,
    child: Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kProBg,
        border: Border.all(color: kProBd, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Text('🔒', style: TextStyle(fontSize: 28)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kPro, fontWeight: FontWeight.w800, fontSize: 14)),
          Text(sublabel, style: const TextStyle(color: kMuted, fontSize: 12)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: kProBd, borderRadius: BorderRadius.circular(99)),
          child: const Text('→', style: TextStyle(color: kPro, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
    ),
  );
}

// ─── Field Input ──────────────────────────────────────────────────────────────
class FieldInput extends StatelessWidget {
  final String label;
  final String? placeholder;
  final String value;
  final ValueChanged<String> onChanged;
  final bool multiline;
  final TextInputType? keyboard;

  const FieldInput({
    super.key, required this.label, required this.value,
    required this.onChanged, this.placeholder, this.multiline = false,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: const TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, color: kMuted, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: value,
        onChanged: onChanged,
        keyboardType: keyboard,
        maxLines: multiline ? 3 : 1,
        decoration: InputDecoration(
          hintText: placeholder,
          filled: true, fillColor: kBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: kBorder, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: kBorder, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: kText, width: 1.5)),
        ),
        style: const TextStyle(fontSize: 14, color: kText),
      ),
      const SizedBox(height: 10),
    ],
  );
}

// ─── Toggle Switch ────────────────────────────────────────────────────────────
class ToggleRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const ToggleRow({
    super.key, required this.label, required this.value,
    required this.onChanged, this.sublabel, this.activeColor = kBlue,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: value ? activeColor.withOpacity(0.08) : kBg,
        border: Border.all(color: value ? activeColor.withOpacity(0.4) : kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kText)),
          if (sublabel != null)
            Text(sublabel!, style: const TextStyle(fontSize: 11, color: kMuted)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: activeColor),
      ]),
    ),
  );
}

// ─── Amount Display ───────────────────────────────────────────────────────────
class AmountDisplay extends StatelessWidget {
  final double amount;
  final bool isIncome;
  final String currency;

  const AmountDisplay({super.key, required this.amount, required this.isIncome,
    this.currency = 'MYR'});

  @override
  Widget build(BuildContext context) => Text(
    '${isIncome ? '+' : '-'}${amount >= 1000 ? 'RM ${(amount/1000).toStringAsFixed(1)}k' : 'RM ${amount.toStringAsFixed(2)}'}',
    style: TextStyle(
      fontSize: 14, fontWeight: FontWeight.w800,
      color: isIncome ? kGreen : kRed,
      fontFamily: 'Georgia',
    ),
  );
}

// ─── Bottom Sheet wrapper ─────────────────────────────────────────────────────
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget child,
  bool fullHeight = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: kSurface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * (fullHeight ? 0.96 : 0.92)),
  builder: (_) => child,
);

// ─── Month Label ──────────────────────────────────────────────────────────────
String monthLabel(String ym, String lang) {
  final d = DateTime.parse('$ym-01');
  final months = lang == 'zh'
    ? ['一月','二月','三月','四月','五月','六月','七月','八月','九月','十月','十一月','十二月']
    : ['January','February','March','April','May','June','July','August','September','October','November','December'];
  return '${months[d.month - 1]} ${d.year}';
}
