import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../constants.dart';
import '../services/ai_service.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/sub_state.dart';
import 'sub_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
// BANK IMPORT SCREEN — PDF bank statement → transactions via Claude AI
// ════════════════════════════════════════════════════════════════════════════
class BankImportScreen extends StatefulWidget {
  const BankImportScreen({super.key});
  @override State<BankImportScreen> createState() => _BankImportScreenState();
}

class _BankImportScreenState extends State<BankImportScreen> {
  // ── State ────────────────────────────────────────────────────────────────
  _Step _step = _Step.pick;
  String? _fileName;
  String? _fileBase64;
  bool    _parsing  = false;
  bool    _saving   = false;
  String? _error;
  List<_ParsedTx> _parsed   = [];
  List<bool>      _selected = [];

  // ── Pick PDF ─────────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _error = 'Could not read file. Try again.');
      return;
    }
    setState(() {
      _fileName   = file.name;
      _fileBase64 = base64Encode(file.bytes!);
      _step       = _Step.preview;
    });
  }

  // ── Parse via Gemini AI ──────────────────────────────────────────────────
  Future<void> _parse() async {
    if (_fileBase64 == null) return;
    setState(() { _parsing = true; _error = null; _parsed = []; });

    try {
      final allCats = [...incomeCategories, ...expenseCategories];
      final catList = allCats.map((c) => '${c.id}: ${c.enLabel}').join(', ');

      final list = await AiService.parseBankStatement(
        base64Pdf: _fileBase64!,
        catList:   catList,
      );

      final parsed = list.map((m) => _ParsedTx(
        date:        m['date'] as String,
        description: m['description'] as String,
        amount:      (m['amount'] as num).toDouble(),
        type:        m['type'] as String,
        catId:       m['catId'] as String,
        confidence:  (m['confidence'] as num).toDouble(),
      )).toList();

      setState(() {
        _parsed   = parsed;
        _selected = List.filled(parsed.length, true);
        _step     = parsed.isEmpty ? _Step.preview : _Step.review;
        if (parsed.isEmpty) _error = 'No transactions found. Make sure this is a bank statement PDF.';
      });
    } catch (e) {
      setState(() => _error = 'Parse error: $e');
    } finally {
      setState(() => _parsing = false);
    }
  }

  // ── Import selected ───────────────────────────────────────────────────────
  Future<void> _import() async {
    final app = context.read<AppState>();
    setState(() { _saving = true; _error = null; });

    try {
      final toImport = <Transaction>[];
      for (int i = 0; i < _parsed.length; i++) {
        if (!_selected[i]) continue;
        final p    = _parsed[i];
        final cats = p.type == 'income' ? incomeCategories : expenseCategories;
        final cat  = cats.firstWhere((c) => c.id == p.catId, orElse: () => cats.last);
        final tx   = Transaction(
          id:           DateTime.now().millisecondsSinceEpoch + i,
          type:         p.type,
          catId:        cat.id,
          amountMYR:    p.amount,
          origAmount:   p.amount,
          origCurrency: 'MYR',
          sstKey:       'none',
          sstMYR:       0,
          descEN:       p.description,
          descZH:       p.description,
          date:         p.date,
          entries:      cat.mkEntries(p.amount),
        );
        toImport.add(tx);
      }

      for (final tx in toImport) {
        await app.addOrUpdateTx(tx);
      }

      if (!mounted) return;
      setState(() => _step = _Step.done);
    } catch (e) {
      setState(() => _error = 'Import error: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _reset() => setState(() {
    _step = _Step.pick; _fileName = null; _fileBase64 = null;
    _parsed = []; _selected = []; _error = null;
  });

  int get _selectedCount => _selected.where((s) => s).length;

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubState>();
    if (!sub.isPro) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(title: const Text('🏦  Bank Statement Import')),
        body: _ProGate(),
      );
    }
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('🏦  Bank Statement Import'),
        actions: [
          if (_step == _Step.review)
            TextButton(
              onPressed: _reset,
              child: const Text('Reset', style: TextStyle(color: kMuted)),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_step) {
          _Step.pick    => _PickView(onPick: _pickFile),
          _Step.preview => _PreviewView(
              fileName:  _fileName ?? '',
              parsing:   _parsing,
              error:     _error,
              onParse:   _parse,
              onReplace: _pickFile,
            ),
          _Step.review  => _ReviewView(
              parsed:    _parsed,
              selected:  _selected,
              saving:    _saving,
              error:     _error,
              onToggle:  (i, v) => setState(() => _selected[i] = v),
              onToggleAll: (v) => setState(() => _selected = List.filled(_parsed.length, v)),
              onImport:  _import,
              selectedCount: _selectedCount,
            ),
          _Step.done    => _DoneView(count: _selectedCount, onBack: () => Navigator.pop(context), onMore: _reset),
        },
      ),
    );
  }
}

// ── Steps enum ───────────────────────────────────────────────────────────────
enum _Step { pick, preview, review, done }

// ── Parsed transaction model ─────────────────────────────────────────────────
class _ParsedTx {
  final String date, description, type, catId;
  final double amount, confidence;
  const _ParsedTx({
    required this.date, required this.description,
    required this.type, required this.catId,
    required this.amount, required this.confidence,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// VIEWS
// ════════════════════════════════════════════════════════════════════════════

// ── Step 1: Pick ─────────────────────────────────────────────────────────────
class _PickView extends StatelessWidget {
  final VoidCallback onPick;
  const _PickView({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(color: kBg, border: Border.all(color: kBorder, width: 2), borderRadius: BorderRadius.circular(24)),
            child: const Center(child: Text('📄', style: TextStyle(fontSize: 48))),
          ),
          const SizedBox(height: 24),
          const Text('Import Bank Statement', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kText)),
          const SizedBox(height: 8),
          const Text(
            'Upload your bank statement PDF.\nClaude AI will extract and categorise all transactions automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          const SizedBox(height: 12),
          // Supported banks
          Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final b in ['Maybank', 'CIMB', 'Public Bank', 'RHB', 'Hong Leong', 'AmBank', 'BSN'])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(99)),
                child: Text(b, style: const TextStyle(fontSize: 11, color: kMuted)),
              ),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Select PDF File', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kDark, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Step 2: Preview / Parse ───────────────────────────────────────────────────
class _PreviewView extends StatelessWidget {
  final String fileName;
  final bool parsing;
  final String? error;
  final VoidCallback onParse, onReplace;
  const _PreviewView({required this.fileName, required this.parsing, this.error, required this.onParse, required this.onReplace});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Text('📄', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fileName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kText), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              const Text('Ready to parse', style: TextStyle(fontSize: 12, color: kMuted)),
            ])),
            TextButton(onPressed: onReplace, child: const Text('Change', style: TextStyle(color: kMuted, fontSize: 12))),
          ]),
        ),
        const SizedBox(height: 20),
        if (parsing) ...[
          const CircularProgressIndicator(color: kDark, strokeWidth: 2),
          const SizedBox(height: 16),
          const Text('Claude AI is reading your statement...', style: TextStyle(color: kMuted)),
          const SizedBox(height: 6),
          const Text('This may take 15–30 seconds', style: TextStyle(fontSize: 12, color: kMuted)),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCDD7FF))),
            child: Row(children: [
              const Text('🤖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Claude AI will read the PDF and extract all transactions, dates, and amounts automatically.', style: TextStyle(fontSize: 13, color: Color(0xFF3344AA)))),
            ]),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: kRedBd)),
              child: Text(error!, style: const TextStyle(color: kRed, fontSize: 13)),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: onParse,
              style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('✨ Parse with AI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Step 3: Review ────────────────────────────────────────────────────────────
class _ReviewView extends StatelessWidget {
  final List<_ParsedTx> parsed;
  final List<bool> selected;
  final bool saving;
  final String? error;
  final void Function(int, bool) onToggle;
  final void Function(bool) onToggleAll;
  final VoidCallback onImport;
  final int selectedCount;
  const _ReviewView({
    required this.parsed, required this.selected, required this.saving,
    this.error, required this.onToggle, required this.onToggleAll,
    required this.onImport, required this.selectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final allSelected = selected.every((s) => s);

    return Column(children: [
      // Header bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(color: kSurface, border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          Text('${parsed.length} transactions found', style: const TextStyle(fontWeight: FontWeight.w700, color: kText)),
          const Spacer(),
          GestureDetector(
            onTap: () => onToggleAll(!allSelected),
            child: Text(allSelected ? 'Deselect All' : 'Select All', style: const TextStyle(fontSize: 13, color: kMuted, decoration: TextDecoration.underline)),
          ),
        ]),
      ),

      // List
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: parsed.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: kBorder, indent: 16, endIndent: 16),
          itemBuilder: (_, i) {
            final tx  = parsed[i];
            final cat = [...incomeCategories, ...expenseCategories].firstWhere((c) => c.id == tx.catId, orElse: () => expenseCategories.last);
            final isInc = tx.type == 'income';
            return CheckboxListTile(
              value:    selected[i],
              onChanged: (v) => onToggle(i, v ?? false),
              activeColor: kDark,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: Row(children: [
                Text(cat.icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tx.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${tx.date}  ·  ${cat.enLabel}', style: const TextStyle(fontSize: 11, color: kMuted)),
                ])),
              ]),
              subtitle: null,
              secondary: Text(
                '${isInc ? '+' : '-'} RM ${fmt.format(tx.amount)}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: isInc ? kGreen : kRed),
              ),
            );
          },
        ),
      ),

      // Error
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kRedBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: kRedBd)),
            child: Text(error!, style: const TextStyle(color: kRed, fontSize: 13)),
          ),
        ),

      // Bottom bar
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
        child: SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: (selectedCount > 0 && !saving) ? onImport : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: kDark, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Import $selectedCount Transaction${selectedCount == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ),
    ]);
  }
}

// ── Step 4: Done ──────────────────────────────────────────────────────────────
class _DoneView extends StatelessWidget {
  final int count;
  final VoidCallback onBack, onMore;
  const _DoneView({required this.count, required this.onBack, required this.onMore});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('✅', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 20),
          Text('$count Transaction${count == 1 ? '' : 's'} Imported!', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kText)),
          const SizedBox(height: 8),
          const Text('All selected transactions have been added to your records.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: kMuted)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: onBack,
              style: ElevatedButton.styleFrom(backgroundColor: kDark, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Back to Records', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onMore, child: const Text('Import Another Statement', style: TextStyle(color: kMuted))),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRO GATE — shown when feature requires subscription
// ════════════════════════════════════════════════════════════════════════════
class _ProGate extends StatelessWidget {
  const _ProGate();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1E0A3C), Color(0xFF3B0764)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: Text('✦', style: TextStyle(fontSize: 36, color: Colors.white))),
            ),
            const SizedBox(height: 24),
            const Text('Pro Feature', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kText)),
            const SizedBox(height: 10),
            const Text(
              'This feature is available for Pro subscribers.\nUpgrade to unlock AI-powered tools.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: kMuted, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () => showSubSheet(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E0A3C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

