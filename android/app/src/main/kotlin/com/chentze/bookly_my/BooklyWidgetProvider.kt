package com.bookly.my

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Bookly MY home-screen widget (Phase 4 #26).
 * Renders the active company's current-month summary. All text is supplied by
 * the Flutter app via home_widget's SharedPreferences; this class only paints.
 * The two buttons deep-link back into the app via bookly://add?type=...
 */
class BooklyWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.bookly_widget).apply {
                setTextViewText(R.id.w_company, widgetData.getString("company", "Bookly MY"))
                setTextViewText(R.id.w_net_label, widgetData.getString("lblNet", "This month"))
                setTextViewText(R.id.w_net, widgetData.getString("net", "RM 0.00"))
                setTextViewText(R.id.w_income_label, widgetData.getString("lblIncome", "Income"))
                setTextViewText(R.id.w_income, widgetData.getString("income", "RM 0.00"))
                setTextViewText(R.id.w_expense_label, widgetData.getString("lblExpense", "Expense"))
                setTextViewText(R.id.w_expense, widgetData.getString("expense", "RM 0.00"))
                setTextViewText(R.id.w_btn_income, widgetData.getString("btnIncome", "+ Income"))
                setTextViewText(R.id.w_btn_expense, widgetData.getString("btnExpense", "+ Expense"))

                // Tap the card body → just open the app.
                setOnClickPendingIntent(
                    R.id.w_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bookly://home")
                    )
                )
                // Quick-add buttons → open the matching add-transaction sheet.
                setOnClickPendingIntent(
                    R.id.w_btn_income,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bookly://add?type=income")
                    )
                )
                setOnClickPendingIntent(
                    R.id.w_btn_expense,
                    HomeWidgetLaunchIntent.getActivity(
                        context, MainActivity::class.java, Uri.parse("bookly://add?type=expense")
                    )
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
