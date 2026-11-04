package com.spotnik.ephemeron

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Shared layout update logic for all ephemeron home-screen widgets.
 * [openUri] optionally deep-links the tap (ephemeron://widget/<action>)
 * instead of just opening the app. */
abstract class EphemeronWidgetProvider(private val titleKey: String, private val bodyKey: String, private val imageKey: String, private val openUri: String? = null) : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.ephemeron_widget).apply {
                val pendingIntent = if (openUri != null) {
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, android.net.Uri.parse(openUri))
                } else {
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                }
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)
                val title = widgetData.getString(titleKey, null) ?: "ephemeron"
                val body = widgetData.getString(bodyKey, null) ?: ""
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_message, body)
                val image = widgetData.getString(imageKey, null)
                if (image != null) {
                    val bmp = BitmapFactory.decodeFile(image)
                    if (bmp != null) {
                        setImageViewBitmap(R.id.widget_img, bmp)
                        setViewVisibility(R.id.widget_img, View.VISIBLE)
                    } else {
                        setViewVisibility(R.id.widget_img, View.GONE)
                    }
                } else {
                    setViewVisibility(R.id.widget_img, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

class MonthCalendarWidgetProvider : EphemeronWidgetProvider("month_calendar_title", "month_calendar_body", "month_calendar_image")
class PendingTasksWidgetProvider : EphemeronWidgetProvider("pending_tasks_title", "pending_tasks_body", "pending_tasks_image")
class MatrixWidgetProvider : EphemeronWidgetProvider("matrix_title", "matrix_body", "matrix_image")
class FocusTimerWidgetProvider : EphemeronWidgetProvider("focus_timer_title", "focus_timer_body", "focus_timer_image")
class OneNoteWidgetProvider : EphemeronWidgetProvider("one_note_title", "one_note_body", "one_note_image")
class NextEventsWidgetProvider : EphemeronWidgetProvider("next_events_title", "next_events_body", "next_events_image")
class CountdownWidgetProvider : EphemeronWidgetProvider("countdown_title", "countdown_body", "countdown_image")
class HabitsTodayWidgetProvider : EphemeronWidgetProvider("habits_today_title", "habits_today_body", "habits_today_image")
class DayAgendaWidgetProvider : EphemeronWidgetProvider("day_agenda_title", "day_agenda_body", "day_agenda_image")
class NextMeetingWidgetProvider : EphemeronWidgetProvider("next_meeting_title", "next_meeting_body", "next_meeting_image")
class FreeBusyWidgetProvider : EphemeronWidgetProvider("free_busy_title", "free_busy_body", "free_busy_image")
class TasksDueTodayWidgetProvider : EphemeronWidgetProvider("tasks_due_today_title", "tasks_due_today_body", "tasks_due_today_image")
class InboxTasksWidgetProvider : EphemeronWidgetProvider("inbox_tasks_title", "inbox_tasks_body", "inbox_tasks_image")
class SmartListWidgetProvider : EphemeronWidgetProvider("smart_list_title", "smart_list_body", "smart_list_image")
class TagTasksWidgetProvider : EphemeronWidgetProvider("tag_tasks_title", "tag_tasks_body", "tag_tasks_image")
class SubtaskProgressWidgetProvider : EphemeronWidgetProvider("subtask_progress_title", "subtask_progress_body", "subtask_progress_image")
class TaskCountsWidgetProvider : EphemeronWidgetProvider("task_counts_title", "task_counts_body", "task_counts_image")
class MatrixCountsWidgetProvider : EphemeronWidgetProvider("matrix_counts_title", "matrix_counts_body", "matrix_counts_image")
class HabitStreakWidgetProvider : EphemeronWidgetProvider("habit_streak_title", "habit_streak_body", "habit_streak_image")
class HabitCompletionRateWidgetProvider : EphemeronWidgetProvider("habit_completion_rate_title", "habit_completion_rate_body", "habit_completion_rate_image")
class HabitHeatmapWidgetProvider : EphemeronWidgetProvider("habit_heatmap_title", "habit_heatmap_body", "habit_heatmap_image")
class FocusMinutesWidgetProvider : EphemeronWidgetProvider("focus_minutes_title", "focus_minutes_body", "focus_minutes_image")
class PomodoroWidgetProvider : EphemeronWidgetProvider("pomodoro_title", "pomodoro_body", "pomodoro_image")
class PinnedNoteWidgetProvider : EphemeronWidgetProvider("pinned_note_title", "pinned_note_body", "pinned_note_image")
class RecentNotesWidgetProvider : EphemeronWidgetProvider("recent_notes_title", "recent_notes_body", "recent_notes_image")
class QuickCaptureWidgetProvider : EphemeronWidgetProvider("quick_capture_title", "quick_capture_body", "quick_capture_image", "ephemeron://widget/new_task")
class AllCountdownsWidgetProvider : EphemeronWidgetProvider("all_countdowns_title", "all_countdowns_body", "all_countdowns_image")
class DaysSinceWidgetProvider : EphemeronWidgetProvider("days_since_title", "days_since_body", "days_since_image")
class NextAlarmWidgetProvider : EphemeronWidgetProvider("next_alarm_title", "next_alarm_body", "next_alarm_image")
class AlarmStatusWidgetProvider : EphemeronWidgetProvider("alarm_status_title", "alarm_status_body", "alarm_status_image")
class SyncStatusWidgetProvider : EphemeronWidgetProvider("sync_status_title", "sync_status_body", "sync_status_image")
class BackupStatusWidgetProvider : EphemeronWidgetProvider("backup_status_title", "backup_status_body", "backup_status_image")
class QuickActionsWidgetProvider : EphemeronWidgetProvider("quick_actions_title", "quick_actions_body", "quick_actions_image", "ephemeron://widget/new_task")
class SearchWidgetWidgetProvider : EphemeronWidgetProvider("search_widget_title", "search_widget_body", "search_widget_image", "ephemeron://widget/search")
class DailySummaryWidgetProvider : EphemeronWidgetProvider("daily_summary_title", "daily_summary_body", "daily_summary_image")
class WeeklyChartWidgetProvider : EphemeronWidgetProvider("weekly_chart_title", "weekly_chart_body", "weekly_chart_image")
class PowerStatusWidgetProvider : EphemeronWidgetProvider("power_status_title", "power_status_body", "power_status_image")
class OverdueBadgeWidgetProvider : EphemeronWidgetProvider("overdue_badge_title", "overdue_badge_body", "overdue_badge_image")
class TagShortcutsWidgetProvider : EphemeronWidgetProvider("tag_shortcuts_title", "tag_shortcuts_body", "tag_shortcuts_image")
class FolderShortcutsWidgetProvider : EphemeronWidgetProvider("folder_shortcuts_title", "folder_shortcuts_body", "folder_shortcuts_image")
class VacationStatusWidgetProvider : EphemeronWidgetProvider("vacation_status_title", "vacation_status_body", "vacation_status_image")