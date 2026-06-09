import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../state/sub_state.dart';

class SubScreen extends StatefulWidget {
  const SubScreen({super.key});
  @override
  State<SubScreen> createState() => _SubScreenState();
}

class _SubScreenState extends State<SubScreen> {
  bool _yearly  = true;
  bool _loading = false;
  bool _restore = false;

  Future<void> _purchase(SubState sub) async {
    setState(() => _loading = true);
    final ok = await sub.purchasePlan(_yearly);
    if (mounted) {
      setState(() => _loading = false);
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🎉 Welcome to Bookly PRO!'),
            backgroundColor: kPro,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Purchase failed. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _restorePurchases(SubState sub) async {
    setState(() => _restore = true);
    final ok = await sub.restorePurchases();
    if (mounted) {
      setState(() => _restore = false);
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Purchase restored!'),
            backgroundColor: kGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous purchase found.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubState>();
    final t   = const L10n('en');

    return Container(
      decoration: const BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ────────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 14, bottom: 6),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: kBorder, borderRadius: BorderRadius.circular(99)),
              ),
            ),

            // ── Close button ──────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: const BoxDecoration(color: kBg, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 18, color: kMuted),
                ),
              ),
            ),

            // ── Title ─────────────────────────────────────────────────
            const Text('✨', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            const Text(
              'Bookly PRO',
              style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, color: kPro),
            ),
            const Text(
              'Remove all ads & unlock everything',
              style: TextStyle(fontSize: 14, color: kMuted),
            ),
            const SizedBox(height: 20),

            // ── Ad explanation banner ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kGoldBg,
                border: Border.all(color: kGoldBd),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📺', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Ads appear when you:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kGold)),
                        SizedBox(height: 4),
                        Text('• Save or export invoices & payslips',
                          style: TextStyle(fontSize: 12, color: kGold)),
                        Text('• Every few minutes while using the app',
                          style: TextStyle(fontSize: 12, color: kGold)),
                        SizedBox(height: 4),
                        Text('Subscribe to remove all ads permanently.',
                          style: TextStyle(fontSize: 12, color: kGold, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Features list ─────────────────────────────────────────
            ...L10n.features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Text(f.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Expanded(child: Text(f.$2,
                  style: const TextStyle(fontSize: 13, color: kText))),
              ]),
            )),
            const SizedBox(height: 20),

            // ── Plan toggle ───────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: kBg,
                border: Border.all(color: kBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                _PlanTab(
                  label: 'Monthly',
                  price: 'RM 9.90/mo',
                  badge: null,
                  selected: !_yearly,
                  onTap: () => setState(() => _yearly = false),
                ),
                _PlanTab(
                  label: 'Yearly',
                  price: 'RM 49.90/yr',
                  badge: 'Save 58%',
                  selected: _yearly,
                  onTap: () => setState(() => _yearly = true),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Subscribe button ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : () => _purchase(sub),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPro,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                    : Text(
                        _yearly
                            ? 'Subscribe Yearly – RM 49.90'
                            : 'Subscribe Monthly – RM 9.90',
                        style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Restore ───────────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: _restore ? null : () => _restorePurchases(sub),
                child: _restore
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Restore Purchases',
                        style: TextStyle(color: kMuted, fontSize: 13)),
              ),
            ),

            // ── Legal note ────────────────────────────────────────────
            const Center(
              child: Text(
                'Subscription auto-renews. Cancel anytime in Google Play.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: kMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plan tab widget ───────────────────────────────────────────────────────────
class _PlanTab extends StatelessWidget {
  final String label, price;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PlanTab({
    required this.label,
    required this.price,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kPro : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : kMuted)),
          const SizedBox(height: 2),
          Text(price,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white70 : kText)),
          if (badge != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white24 : kGreenBg,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(badge!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : kGreen)),
            ),
          ],
        ]),
      ),
    ),
  );
}

// ── Helper to show the subscription sheet from anywhere ──────────────────────
void showSubSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom),
      child: const SubScreen(),
    ),
  );
}
