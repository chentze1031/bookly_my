import 'dart:convert';
import 'package:http/http.dart' as http;

class AiService {
  // 1. 修复模型名称：增加 "models/" 前缀，这是最稳妥写法
  static const _apiKey = 'AIzaSyDl76uz1e5aoGb9gZXu6EvL6iZLmh_rt-k';
  static const _embedModel = 'models/text-embedding-004'; // 推荐用这个，比 001 更精准

  static String get _baseUrl => 'https://generativelanguage.googleapis.com/v1beta';

  // ── 1. 获取向量 (Embedding) ───────────────────────────────────────────────
  static Future<List<double>> getEmbedding(String text) async {
    final url = '$_baseUrl/$_embedModel:embedContent?key=$_apiKey';
    
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': _embedModel,
        'content': {
          'parts': [{'text': text}]
        },
        // 建议增加任务类型，针对分类优化
        'taskType': 'CLASSIFICATION', 
      }),
    );

    if (res.statusCode != 200) throw Exception('Embedding error: ${res.body}');
    
    final data = jsonDecode(res.body);
    return (data['embedding']['values'] as List).cast<double>();
  }

  // ── 2. 自动分类 (维持原有逻辑，修复 URL) ───────────────────────────────────
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

Respond ONLY with valid JSON, no markdown:
{
  "catId": "<exact category id from list>",
  "confidence": <0.0 to 1.0>,
  "reason": "<one sentence in English>"
}
''';
    // 注意这里调用了更新后的 _call
    final body = await _call(prompt);
    final json = _parseJson(body);
    return AutoCatResult(
      catId:      json['catId'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      reason:     json['reason'] as String,
    );
  }

  // ── 内部方法：修复了模型路径拼接 ───────────────────────────────────────────
  static Future<String> _call(String prompt) async {
    // 修复：确保 URL 包含完整的模型路径
    final url = '$_baseUrl/$_flashModel:generateContent?key=$_apiKey';
    
    final res = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [{ 'parts': [{ 'text': prompt }] }],
        'generationConfig': { 
          'temperature': 0.1, 
          'maxOutputTokens': 1024,
          'responseMimeType': 'application/json' // 强制返回 JSON 格式
        },
      }),
    );
    
    if (res.statusCode != 200) throw Exception('Gemini error ${res.statusCode}: ${res.body}');
    return _extractText(res.body);
  }

  // 其他解析方法 (forecast, parseBankStatement) 记得也把内部 post 
  // 的 endpoint 指向最新的 url 格式即可。

  static String _extractText(String body) {
    final data  = jsonDecode(body) as Map<String, dynamic>;
    if (data['candidates'] == null || (data['candidates'] as List).isEmpty) {
      throw Exception('Gemini returned no candidates');
    }
    final cands = data['candidates'] as List;
    final parts = (cands.first['content'] as Map<String, dynamic>)['parts'] as List;
    return parts.where((p) => p['text'] != null).map((p) => p['text'] as String).join('');
  }

  static Map<String, dynamic> _parseJson(String raw) {
    // 增加一层清理逻辑，防止模型带上 markdown 标签
    final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    return jsonDecode(clean) as Map<String, dynamic>;
  }
}
