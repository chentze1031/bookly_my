import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inventory_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// LOW STOCK REMINDER (Phase 3 Task #17 — system notification)
//
// Fires a local notification when there are low/out-of-stock items, at most
// once per calendar day. Triggered after a sale deducts stock and when the
// inventory screen loads. Fully guarded so failures never break the app.
// ════════════════════════════════════════════════════════════════════════════
class LowStockReminder {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const _prefKey = 'bly_lowstock_reminded_on';

  static Future<void> _init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _inited = true;
  }

  /// [lowOrOut] = items at/below threshold or out of stock.
  static Future<void> checkAndNotify(List<InventoryItem> lowOrOut, String lang) async {
    try {
      if (lowOrOut.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString(_prefKey) == today) return; // already reminded today

      await _init();

      final zh    = lang == 'zh';
      final count = lowOrOut.length;
      final names = lowOrOut.take(3).map((i) => i.name).join('、');
      final more  = count > 3 ? (zh ? ' 等' : '…') : '';
      final title = zh ? '库存不足提醒' : 'Low stock alert';
      final body  = zh
          ? '$count 项库存偏低：$names$more'
          : '$count item(s) running low: $names$more';

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'low_stock',
          'Low Stock',
          channelDescription: 'Reminds you when inventory items run low',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _plugin.show(8802, title, body, details);
      await prefs.setString(_prefKey, today);
    } catch (e) {
      debugPrint('LowStockReminder failed: $e');
    }
  }
}
