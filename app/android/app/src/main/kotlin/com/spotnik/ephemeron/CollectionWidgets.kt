package com.spotnik.ephemeron

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/** Base for scrollable (collection) home-screen widgets.
 * NOTE: setRemoteAdapter(Intent)/notifyAppWidgetViewDataChanged are deprecated
 * on API 31+, but remain the only APIs available below API 31, so they are
 * kept with Suppress rather than branching on SDK level. */

@Suppress("DEPRECATION")
abstract class CollectionWidgetProvider(private val type: String) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.ephemeron_collection_widget).apply {
                val title = widgetData.getString("${type}_title", null) ?: type
                setTextViewText(R.id.collection_title, title)
                val svc = android.content.Intent(context, EphemeronRemoteViewsService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    putExtra("type", type)
                    data = android.net.Uri.parse(toUri(android.content.Intent.URI_INTENT_SCHEME))
                }
                setRemoteAdapter(R.id.collection_list, svc)
                setEmptyView(R.id.collection_list, R.id.collection_empty)
            }
            appWidgetManager.updateAppWidget(id, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.collection_list)
        }
    }
}

@Suppress("DEPRECATION")
class PendingTasksCollectionProvider : CollectionWidgetProvider("pending_tasks_collection")
@Suppress("DEPRECATION")
class DayAgendaCollectionProvider : CollectionWidgetProvider("day_agenda_collection")
@Suppress("DEPRECATION")
class RecentNotesCollectionProvider : CollectionWidgetProvider("recent_notes_collection")
@Suppress("DEPRECATION")
class CountdownsCollectionProvider : CollectionWidgetProvider("all_countdowns_collection")
@Suppress("DEPRECATION")
class HabitsTodayCollectionProvider : CollectionWidgetProvider("habits_today_collection")

class EphemeronRemoteViewsService : android.widget.RemoteViewsService() {
    override fun onGetViewFactory(intent: android.content.Intent): RemoteViewsFactory {
        val type = intent.getStringExtra("type") ?: "pending_tasks_collection"
        return EphemeronRemoteViewsFactory(applicationContext, type)
    }
}

class EphemeronRemoteViewsFactory(
    private val context: Context,
    private val type: String,
) : android.widget.RemoteViewsService.RemoteViewsFactory {
    private val items = mutableListOf<Pair<String, String>>()

    override fun onCreate() {}
    override fun onDataSetChanged() {
        items.clear()
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("${type}_items", "[]")
        try {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.optJSONObject(i)
                val id = o?.optString("id") ?: ""
                val title = o?.optString("title") ?: arr.optString(i)
                items.add(Pair(id, title))
            }
        } catch (_: Exception) {
        }
    }
    override fun onDestroy() { items.clear() }
    override fun getCount(): Int = items.size
    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.ephemeron_collection_item)
        val pair = items.getOrElse(position) { Pair("", "") }
        views.setTextViewText(R.id.collection_item_text, pair.second)
        val kind = when (type) {
            "pending_tasks_collection" -> "task"
            "habits_today_collection" -> "habit"
            else -> ""
        }
        if (kind.isNotEmpty() && pair.first.isNotEmpty()) {
            val bgIntent = es.antonborri.home_widget.HomeWidgetBackgroundIntent.getBroadcast(
                context, android.net.Uri.parse("ephemeron://toggle/$kind/${pair.first}")
            )
            views.setOnClickPendingIntent(R.id.collection_item_toggle, bgIntent)
        } else {
            views.setViewVisibility(R.id.collection_item_toggle, android.view.View.GONE)
        }
        return views
    }
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}