import 'package:home_widget/home_widget.dart';

/// Pushes the active company's monthly summary to the Android home-screen
/// widget (Phase 4 #26). The app pre-formats every value + localized label so
/// the native widget only has to render text — no logic on the native side.
class WidgetService {
  // Matches the AppWidgetProvider class name (com.bookly.my.BooklyWidgetProvider).
  static const _android = 'BooklyWidgetProvider';

  static Future<void> update({
    required String company,
    required String net,
    required String income,
    required String expense,
    required String lblNet,
    required String lblIncome,
    required String lblExpense,
    required String btnIncome,
    required String btnExpense,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>('company', company);
      await HomeWidget.saveWidgetData<String>('net', net);
      await HomeWidget.saveWidgetData<String>('income', income);
      await HomeWidget.saveWidgetData<String>('expense', expense);
      await HomeWidget.saveWidgetData<String>('lblNet', lblNet);
      await HomeWidget.saveWidgetData<String>('lblIncome', lblIncome);
      await HomeWidget.saveWidgetData<String>('lblExpense', lblExpense);
      await HomeWidget.saveWidgetData<String>('btnIncome', btnIncome);
      await HomeWidget.saveWidgetData<String>('btnExpense', btnExpense);
      await HomeWidget.updateWidget(androidName: _android);
    } catch (_) {
      // Widget not placed yet, or a platform without home widgets — ignore.
    }
  }
}
