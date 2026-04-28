import 'dart:convert';
import 'package:http/http.dart' as http;

// ════════════════════════════════════════════════════════════════════════════
// AI SERVICE — Gemini API for Bookly MY features
// Set key via: flutter run --dart-define=GEMINI_KEY=AIzaSyDl76uz1e5aoGb9gZXu6EvL6iZLmh_rt-k
// ════════════════════════════════════════════════════════════════════════════
class AiService {
  static const _apiKey = 'AIzaSyDl76uz1e5aoGb9gZXu6EvL6iZLmh_rt-k';
  static const _litemodel  = 'gemini-2.5-flash-lite';
  static String get _endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/$_liteModel:generateContent?key=$_apiKey';

  // ── 1. Auto-categorise ───────────────────────────────────────────────────
  static Future<AutoCatResult> categorise({
    required String description,
    required String type,
    required double amount,
    required List<String> categoryIds,
    required Map<String, String> categoryLabels,
  }) async {
    final catList = categoryIds.map((id) => '- $id: ${categoryLabels[id]}').join('\n');
    final prompt = '''
You are a Malaysia SME accounting assistant. Classify this transaction into ONE category.

Transaction:
- Type: $type
- Description: "$description"
- Amount: MYR ${amount.toStringAsFixed(2)}

Available categories:
$catList

Respond ONLY with valid JSON, no markdown, no explanation:
{
  "catId": "<exact category id from list>",
  "confidence": <0.0 to 1.0>,
  "reason": "<one sentence in English>"
}
''';
    final body = await _call(prompt);
    final json = _parseJson(body);
    return AutoCatResult(
      catId:      json['catId'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      reason:     json['reason'] as String,
    );
  }

  // ── 2. Cash flow forecast ─────────────────────────────────────────────────
  static Future<CashflowForecast> forecast({
    required List<MonthSummary> history,
    required String currency,
  }) async {
    final historyStr = history.map((m) =>
      '${m.label}: income=${m.income.toStringAsFixed(0)}, expense=${m.expense.toStringAsFixed(0)}, net=${m.net.toStringAsFixed(0)}'
    ).join('\n');
    final prompt = '''
You are a Malaysia SME financial advisor. Analyse this cash flow history and forecast the next 3 months.

Historical data (MYR):
$historyStr

Respond ONLY with valid JSON, no markdown:
{
  "forecast": [
    { "label": "Month Year", "income": 0.0, "expense": 0.0, "net": 0.0 },
    { "label": "Month Year", "income": 0.0, "expense": 0.0, "net": 0.0 },
    { "label": "Month Year", "income": 0.0, "expense": 0.0, "net": 0.0 }
  ],
  "trend": "growing|stable|declining",
  "insights": [
    "insight 1 in English (max 15 words)",
    "insight 2 in English (max 15 words)",
    "insight 3 in English (max 15 words)"
  ],
  "alert": null
}
''';
    final body = await _call(prompt);
    final json = _parseJson(body);
    final forecastList = (json['forecast'] as List).map((f) => MonthSummary(
      label:   f['label'] as String,
      income:  (f['income'] as num).toDouble(),
      expense: (f['expense'] as num).toDouble(),
    )).toList();
    return CashflowForecast(
      forecast: forecastList,
      trend:    json['trend'] as String,
      insights: List<String>.from(json['insights'] as List),
      alert:    json['alert'] as String?,
    );
  }

  // ── 3. Parse PDF bank statement ───────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> parseBankStatement({
    required String base64Pdf,
    required String catList,
  }) async {
    final prompt = '''
You are a Malaysia bank statement parser. Extract ALL transactions from this PDF.

Categories to use:
$catList

Rules:
- Credits/deposits = income, Debits/withdrawals = expense
- Date format: YYYY-MM-DD, Amount: MYR positive numbers only
- If unsure use "other_income" or "other_expense"

Respond ONLY with a valid JSON array, no markdown:
[{ "date":"YYYY-MM-DD","description":"...","amount":0.00,"type":"income|expense","catId":"...","confidence":0.0 }]

If not a bank statement, return: []
''';
    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{
          'parts': [
            { 'inline_data': { 'mime_type': 'application/pdf', 'data': base64Pdf } },
            { 'text': prompt },
          ],
        }],
        'generationConfig': { 'temperature': 0.1, 'maxOutputTokens': 8192 },
      }),
    );
    if (res.statusCode != 200) throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    final text  = _extractText(res.body);
    final clean = text.replaceAll('```json', '').replaceAll('```', '').trim();
    return (jsonDecode(clean) as List).cast<Map<String, dynamic>>();
  }

  // ── Internal: text-only prompt ───────────────────────────────────────────
  static Future<String> _call(String prompt) async {
    final res = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{ 'parts': [{ 'text': prompt }] }],
        'generationConfig': { 'temperature': 0.1, 'maxOutputTokens': 1024 },
      }),
    );
    if (res.statusCode != 200) throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    return _extractText(res.body);
  }

  static String _extractText(String body) {
    final data  = jsonDecode(body) as Map<String, dynamic>;
    final cands = data['candidates'] as List;
    if (cands.isEmpty) throw Exception('Gemini returned no candidates');
    final parts = (cands.first['content'] as Map<String, dynamic>)['parts'] as List;
    return parts.where((p) => p['text'] != null).map((p) => p['text'] as String).join('');
  }

  static Map<String, dynamic> _parseJson(String raw) =>
      jsonDecode(raw.replaceAll('```json', '').replaceAll('```', '').trim()) as Map<String, dynamic>;
}

// ════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ════════════════════════════════════════════════════════════════════════════
class AutoCatResult {
  final String catId, reason;
  final double confidence;
  const AutoCatResult({required this.catId, required this.confidence, required this.reason});
}

class MonthSummary {
  final String label;
  final double income, expense;
  double get net => income - expense;
  const MonthSummary({required this.label, required this.income, required this.expense});
}

class CashflowForecast {
  final List<MonthSummary> forecast;
  final String trend;
  final List<String> insights;
  final String? alert;
  const CashflowForecast({required this.forecast, required this.trend, required this.insights, this.alert});
}
