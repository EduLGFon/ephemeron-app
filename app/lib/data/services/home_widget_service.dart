// Service for pushing data to Android home-screen widgets via home_widget.
// Widgets are rendered natively (see android/.../HomeWidgets.kt); this
// service stores the small text/image payload each widget displays.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

/// One home-screen widget shipped by the app. [provider] is the Kotlin
/// AppWidgetProvider class name; [keyPrefix] is the SharedPreferences key
/// prefix its provider reads (see HomeWidgets.kt).
class HomeWidgetDefinition {
  const HomeWidgetDefinition(this.provider, this.keyPrefix);
  final String provider;
  final String keyPrefix;
}

const List<HomeWidgetDefinition> homeWidgets = <HomeWidgetDefinition>[
  HomeWidgetDefinition('MonthCalendarWidgetProvider', 'month_calendar'),
  HomeWidgetDefinition('WeekCalendarWidgetProvider', 'week_calendar'),
  HomeWidgetDefinition('PendingTasksWidgetProvider', 'pending_tasks'),
  HomeWidgetDefinition('MatrixWidgetProvider', 'matrix'),
  HomeWidgetDefinition('FocusTimerWidgetProvider', 'focus_timer'),
  HomeWidgetDefinition('OneNoteWidgetProvider', 'one_note'),
  HomeWidgetDefinition('NextEventsWidgetProvider', 'next_events'),
  HomeWidgetDefinition('CountdownWidgetProvider', 'countdown'),
  HomeWidgetDefinition('HabitsTodayWidgetProvider', 'habits_today'),
  HomeWidgetDefinition('DayAgendaWidgetProvider', 'day_agenda'),
  HomeWidgetDefinition('NextMeetingWidgetProvider', 'next_meeting'),
  HomeWidgetDefinition('FreeBusyWidgetProvider', 'free_busy'),
  HomeWidgetDefinition('TasksDueTodayWidgetProvider', 'tasks_due_today'),
  HomeWidgetDefinition('InboxTasksWidgetProvider', 'inbox_tasks'),
  HomeWidgetDefinition('SmartListWidgetProvider', 'smart_list'),
  HomeWidgetDefinition('TagTasksWidgetProvider', 'tag_tasks'),
  HomeWidgetDefinition('SubtaskProgressWidgetProvider', 'subtask_progress'),
  HomeWidgetDefinition('TaskCountsWidgetProvider', 'task_counts'),
  HomeWidgetDefinition('MatrixCountsWidgetProvider', 'matrix_counts'),
  HomeWidgetDefinition('HabitStreakWidgetProvider', 'habit_streak'),
  HomeWidgetDefinition(
    'HabitCompletionRateWidgetProvider',
    'habit_completion_rate',
  ),
  HomeWidgetDefinition('HabitHeatmapWidgetProvider', 'habit_heatmap'),
  HomeWidgetDefinition('FocusMinutesWidgetProvider', 'focus_minutes'),
  HomeWidgetDefinition('PomodoroWidgetProvider', 'pomodoro'),
  HomeWidgetDefinition('PinnedNoteWidgetProvider', 'pinned_note'),
  HomeWidgetDefinition('RecentNotesWidgetProvider', 'recent_notes'),
  HomeWidgetDefinition('QuickCaptureWidgetProvider', 'quick_capture'),
  HomeWidgetDefinition('AllCountdownsWidgetProvider', 'all_countdowns'),
  HomeWidgetDefinition('DaysSinceWidgetProvider', 'days_since'),
  HomeWidgetDefinition('NextAlarmWidgetProvider', 'next_alarm'),
  HomeWidgetDefinition('AlarmStatusWidgetProvider', 'alarm_status'),
  HomeWidgetDefinition('SyncStatusWidgetProvider', 'sync_status'),
  HomeWidgetDefinition('BackupStatusWidgetProvider', 'backup_status'),
  HomeWidgetDefinition('QuickActionsWidgetProvider', 'quick_actions'),
  HomeWidgetDefinition('SearchWidgetWidgetProvider', 'search_widget'),
  HomeWidgetDefinition('DailySummaryWidgetProvider', 'daily_summary'),
  HomeWidgetDefinition('WeeklyChartWidgetProvider', 'weekly_chart'),
  HomeWidgetDefinition('PowerStatusWidgetProvider', 'power_status'),
  HomeWidgetDefinition('OverdueBadgeWidgetProvider', 'overdue_badge'),
  HomeWidgetDefinition('TagShortcutsWidgetProvider', 'tag_shortcuts'),
  HomeWidgetDefinition('FolderShortcutsWidgetProvider', 'folder_shortcuts'),
  HomeWidgetDefinition('VacationStatusWidgetProvider', 'vacation_status'),
  HomeWidgetDefinition(
    'PendingTasksCollectionProvider',
    'pending_tasks_collection',
  ),
  HomeWidgetDefinition('DayAgendaCollectionProvider', 'day_agenda_collection'),
  HomeWidgetDefinition(
    'RecentNotesCollectionProvider',
    'recent_notes_collection',
  ),
  HomeWidgetDefinition(
    'CountdownsCollectionProvider',
    'all_countdowns_collection',
  ),
  HomeWidgetDefinition(
    'HabitsTodayCollectionProvider',
    'habits_today_collection',
  ),
];

class HomeWidgetService {
  HomeWidgetService();

  /// Runs a home_widget platform call, silently skipping on platforms
  /// without a widget host (e.g. Linux desktop). Never throws.
  Future<void> _widgetCall(Future<void> Function() call) async {
    try {
      await call();
    } on MissingPluginException {
      // No widget host on this platform; degrade gracefully.
    }
  }

  static String encodeItems(List<Map<String, String>> items) {
    final json = items
        .map(
          (e) =>
              '{"id":"${(e['id'] ?? '').replaceAll('"', '\\"')}","title":"${(e['title'] ?? '').replaceAll('"', '\\"')}"}',
        )
        .join(',');
    return '[$json]';
  }

  /// Store a text/image payload for one widget and refresh it.
  Future<void> update({
    required String keyPrefix,
    required String provider,
    String? title,
    String? body,
    String? imagePath,
  }) {
    return _widgetCall(() async {
      if (title != null) {
        await HomeWidget.saveWidgetData<String>('${keyPrefix}_title', title);
      }
      if (body != null) {
        await HomeWidget.saveWidgetData<String>('${keyPrefix}_body', body);
      }
      if (imagePath != null) {
        await HomeWidget.saveWidgetData<String>(
          '${keyPrefix}_image',
          imagePath,
        );
      }
      await HomeWidget.updateWidget(
        androidName: provider,
        qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
      );
    });
  }

  /// Convenience: update by key prefix (provider resolved).
  Future<void> updateByPrefix({
    required String keyPrefix,
    String? title,
    String? body,
    String? imagePath,
  }) async {
    final def = homeWidgets.firstWhere(
      (d) => d.keyPrefix == keyPrefix,
      orElse: () => homeWidgets.first,
    );
    await update(
      keyPrefix: keyPrefix,
      provider: def.provider,
      title: title,
      body: body,
      imagePath: imagePath,
    );
  }

  /// Store a list payload for collection widgets.
  Future<void> updateCollection({
    required String keyPrefix,
    required String provider,
    required List<Map<String, String>> items,
    String? title,
  }) {
    return _widgetCall(() async {
      if (title != null) {
        await HomeWidget.saveWidgetData<String>('${keyPrefix}_title', title);
      }
      final wrapped = encodeItems(items);
      await HomeWidget.saveWidgetData<String>('${keyPrefix}_items', wrapped);
      await HomeWidget.updateWidget(
        androidName: provider,
        qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
      );
    });
  }

  /// Refresh every shipped widget (best-effort).
  Future<void> refreshAll() {
    return _widgetCall(() async {
      for (final def in homeWidgets) {
        await HomeWidget.updateWidget(
          androidName: def.provider,
          qualifiedAndroidName: 'com.spotnik.ephemeron.${def.provider}',
        );
      }
    });
  }
}

final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetService();
});
