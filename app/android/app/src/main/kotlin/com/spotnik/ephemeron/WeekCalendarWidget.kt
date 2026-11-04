package com.spotnik.ephemeron

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Full-week calendar widget: the Flutter side renders the seven-day
 * time grid into a PNG; this provider shows it and layers seven transparent
 * day cells over it so tapping a column opens that day in the app.
 * The title row opens today's week. */
class WeekCalendarWidgetProvider : HomeWidgetProvider() {
    companion object {
        private val DAY_VIEW_IDS = intArrayOf(
            R.id.week_day_0,
            R.id.week_day_1,
            R.id.week_day_2,
            R.id.week_day_3,
            R.id.week_day_4,
            R.id.week_day_5,
            R.id.week_day_6,
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("week_calendar_title", null) ?: "This week"
        val body = widgetData.getString("week_calendar_body", null) ?: ""
        val imagePath = widgetData.getString("week_calendar_image", null)
        val dayKeys = widgetData.getString("week_calendar_days", null)
            ?.split(',')
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(
                context.packageName,
                R.layout.ephemeron_week_calendar_widget,
            ).apply {
                setTextViewText(R.id.week_calendar_title, title)
                setContentDescription(R.id.week_calendar_img, title)
                setOnClickPendingIntent(
                    R.id.week_calendar_title,
                    launch(context, "ephemeron://widget/calendar/today"),
                )

                val bitmap = imagePath?.let { BitmapFactory.decodeFile(it) }
                if (bitmap != null) {
                    setImageViewBitmap(R.id.week_calendar_img, bitmap)
                    setViewVisibility(R.id.week_calendar_img, View.VISIBLE)
                    setViewVisibility(R.id.week_calendar_body, View.GONE)
                } else {
                    setViewVisibility(R.id.week_calendar_img, View.GONE)
                    setTextViewText(R.id.week_calendar_body, body)
                    setViewVisibility(R.id.week_calendar_body, View.VISIBLE)
                }

                DAY_VIEW_IDS.forEachIndexed { index, viewId ->
                    val dayKey = dayKeys.getOrNull(index)
                    if (dayKey == null) {
                        setViewVisibility(viewId, View.GONE)
                    } else {
                        setViewVisibility(viewId, View.VISIBLE)
                        setContentDescription(viewId, "Open $dayKey")
                        setOnClickPendingIntent(
                            viewId,
                            launch(
                                context,
                                "ephemeron://widget/calendar/$dayKey",
                            ),
                        )
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun launch(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse(uri),
        )
}
