import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../constants.dart';

class SettingsService {
  // Per-company (scoped) settings key.
  static String get _key => StorageKeys.settings;
  // Dark mode is a DEVICE preference — shared across all companies, never scoped.
  static const _darkKey = 'bly_settings_dark';

  // Receipt-scan free-trial counter is a DEVICE-local lifetime count (never
  // scoped, never cloud-synced). Non-Pro users get [freeReceiptScanLimit]
  // successful scans before the Pro upsell kicks in.
  static const _receiptScanCountKey = 'bly_receipt_scan_count';
  static const freeReceiptScanLimit = 5;

  static Future<int> receiptScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_receiptScanCountKey) ?? 0;
  }

  static Future<void> incrementReceiptScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt(_receiptScanCountKey) ?? 0;
    await prefs.setInt(_receiptScanCountKey, n + 1);
  }

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
