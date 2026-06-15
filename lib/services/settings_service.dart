import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../constants.dart';

class SettingsService {
  static const _key = StorageKeys.settings;
  static const _darkKey = '${StorageKeys.settings}_dark';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final base = raw != null ? AppSettings.fromMap(jsonDecode(raw)) : const AppSettings();
    // Dark mode is device-local (not part of the cloud-synced settings map).
    return base.copyWith(dark: prefs.getBool(_darkKey) ?? false);
  }

  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toMap()));
    await prefs.setBool(_darkKey, settings.dark);
  }
}
