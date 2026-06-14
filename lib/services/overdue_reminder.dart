import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/accounting_state.dart';
import '../utils.dart';

// ════════════════════════════════════════════════════════════════════════════
// OVERDUE RECEIVABLES REMINDER (Phase 2 Task #8 — system notification)
//
// Fires a local notification when there are overdue receivables, at most once
// per calendar day. Immediate (no scheduling) → no exact-alarm / boot receiver
// needed. Fully guarded so a notification failure never blocks app launch.
// ════════════════════════════════════════════════════════════════════════════
class OverdueReminder {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const _prefKey = 'bly_overdue_reminded_on';

  static Future<void> _init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    // Android 13+ runtime notification permission
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _inited = true;
  }

  /// Show an overdue-receivables reminder at most once per calendar day.
  static Future<void> checkAndNotify(AccountingState acc, String lang) async {
    try {
      final count = acc.overdueArCount;
      final total = acc.totalOverdueAr;
      if (count <= 0) return;

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString(_prefKey) == today) return; // already reminded today

      await _init();

      final zh = lang == 'zh';
      final title = zh ? '逾期收款提醒' : 'Overdue receivables';
      final body  = zh
          ? '$count 张发票逾期，共 ${fmtMYR(total)} 待催收'
          : '$count invoice(s) overdue · ${fmtMYR(total)} to collect';

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'overdue_ar',
          'Overdue Receivables',
          channelDescription: 'Reminds you when customer invoices are overdue',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      await _plugin.show(8801, title, body, details);
      await prefs.setString(_prefKey, today);
    } catch (e) {
      // Best-effort: never let a notification error block startup.
      debugPrint('OverdueReminder failed: $e');
    }
  }
}
