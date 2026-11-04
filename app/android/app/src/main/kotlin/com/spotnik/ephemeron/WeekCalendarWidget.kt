package com.spotnik.ephemeron

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Week calendar widget: the Flutter side renders the configured day range
 * into a wide PNG; this provider shows it with a header (previous, title,
 * next) and layers transparent day cells over it so tapping a column in
 * 7-day mode opens that day in the app. The title tap opens today's week.
 * Previous/next launch the app with a widget action that shifts the
 * persisted anchor and re-renders the widget in the foreground, because the
 * native provider cannot re-render the Flutter image on its own. */
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
        val theme = widgetData.getString("week_calendar_theme", null) ?: "light"
        val dayKeys = widgetData.getString("week_calendar_days", null)
            ?.split(',')
            ?.filter { it.isNotBlank() }
            ?: emptyList()

        val dark = theme == "dark" || theme == "transparent"
        val titleColor = if (dark) Color.WHITE else Color.BLACK
        val rootBg = if (theme == "transparent") Color.TRANSPARENT
            else if (theme == "dark") Color.parseColor("#FF1B1B1D")
            else Color.WHITE

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(
                context.packageName,
                R.layout.ephemeron_week_calendar_widget,
            ).apply {
                setInt(R.id.week_calendar_root, "setBackgroundColor", rootBg)
                setTextViewText(R.id.week_calendar_title, title)
                setTextColor(R.id.week_calendar_title, titleColor)
                setTextColor(R.id.week_calendar_prev, titleColor)
                setTextColor(R.id.week_calendar_next, titleColor)
                setContentDescription(R.id.week_calendar_img, title)
                setOnClickPendingIntent(
                    R.id.week_calendar_title,
                    launch(context, "ephemeron://widget/calendar/today"),
                )
                setOnClickPendingIntent(
                    R.id.week_calendar_prev,
                    launch(context, "ephemeron://widget/calendar/prev"),
                )
                setOnClickPendingIntent(
                    R.id.week_calendar_next,
                    launch(context, "ephemeron://widget/calendar/next"),
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

                if (dayKeys.size == 7) {
                    // Seven tappable day columns aligned with the grid.
                    setOnClickPendingIntent(
                        R.id.week_calendar_img,
                        launch(context, "ephemeron://widget/calendar/today"),
                    )
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
                } else {
                    // Fewer columns: one root tap opens the shown range so
                    // per-day taps cannot misalign with the grid.
                    val anchor = dayKeys.firstOrNull() ?: "today"
                    setOnClickPendingIntent(
                        R.id.week_calendar_img,
                        launch(context, "ephemeron://widget/calendar/$anchor"),
                    )
                    DAY_VIEW_IDS.forEach { viewId ->
                        setViewVisibility(viewId, View.GONE)
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
