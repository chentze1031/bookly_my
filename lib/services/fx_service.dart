import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class FxService {
  static const _cacheKey = 'bly_fx_cache';
  static const _tsKey    = 'bly_fx_ts';
  static const _ttlMs    = 6 * 3600 * 1000; // 6 hours

  /// Load from cache or defaults
  static Future<Map<String, double>> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final ts    = prefs.getInt(_tsKey) ?? 0;
    final raw   = prefs.getString(_cacheKey);
    if (raw != null && DateTime.now().millisecondsSinceEpoch - ts < _ttlMs) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
      } catch (_) {}
    }
    return Map.from(defaultRates);
  }

  /// Fetch live rates from exchangerate-api.com (free, no key)
  /// Returns per-1-unit → MYR map
  static Future<Map<String, double>?> fetchLive() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.exchangerate-api.com/v4/latest/MYR'),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rawRates = data['rates'] as Map<String, dynamic>;
      // rawRates[X] = how many X per 1 MYR → invert to get MYR per 1 X
      final converted = <String, double>{'MYR': 1.0};
      for (final code in defaultRates.keys) {
        if (code == 'MYR') continue;
        final raw = rawRates[code];
        if (raw != null && (raw as num).toDouble() > 0) {
          converted[code] = double.parse(
            (1.0 / (raw as num).toDouble()).toStringAsFixed(6),
          );
        }
      }
      // Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(converted));
      await prefs.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
      return converted;
    } catch (_) {
      return null;
    }
  }
}
