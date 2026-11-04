import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/habits/date_key.dart';
import '../../../core/power/power_saving_manager.dart';
import '../../../core/time/time.dart';
import '../../../features/tasks/application/tasks_providers.dart';
import '../../../features/countdowns/application/countdowns_providers.dart';
import '../../../features/habits/application/habits_providers.dart';
import '../../../features/notes/application/notes_providers.dart';
import '../../../features/focus/application/focus_providers.dart';
import '../../../features/calendar/application/calendar_providers.dart';
import '../../../features/alarms/application/alarm_providers.dart';
import '../../../features/settings/application/settings_providers.dart';
import 'home_widget_service.dart';
import 'home_widget_support.dart';
import 'week_calendar_data.dart';
import 'widget_config_store.dart';
import 'widget_image_service.dart';

/// True when [className] is [provider] either as an exact short name
/// (e.g. `WeekCalendarWidgetProvider`) or as a fully qualified Android class
/// name ending in `.<provider>` (e.g.
/// `com.spotnik.ephemeron.WeekCalendarWidgetProvider`).
bool widgetProviderMatches(String? className, String provider) {
  if (className == null) return false;
  if (className == provider) return true;
  return className.endsWith('.$provider');
}

class HomeWidgetDataBinder {
  HomeWidgetDataBinder(this.ref);
  final Ref ref;

  HomeWidgetService get _svc => ref.read(homeWidgetServiceProvider);
  final Set<String> _touched = <String>{};

  void _mark(String prefix) => _touched.add(prefix);

  Future<void> refreshAll() async {
    _touched.clear();
    await Future.wait([
      _refreshTasks(),
      _refreshCountdowns(),
      _refreshHabits(),
      _refreshNotes(),
      _refreshFocus(),
      _refreshEvents(),
      _refreshWeekCalendar(),
      _refreshMatrix(),
      _refreshAlarms(),
      _refreshTaskVariants(),
      _refreshDailySummary(),
      _refreshSyncStatus(),
      _refreshExtras(),
    ]);
    // Derived last so it can skip keys with dedicated real data.
    await _refreshDerived();
    // Images need a Flutter engine: foreground only, best-effort.
    await _refreshImages();
    // Fill any widget type that has no dedicated wiring yet so pinned
    // widgets are never blank.
    for (final w in homeWidgets) {
      if (_touched.contains(w.keyPrefix)) continue;
      try {
        await _svc.updateByPrefix(
          keyPrefix: w.keyPrefix,
          title: w.keyPrefix.replaceAll('_', ' '),
          body: 'Open ephemeron for details.',
        );
        _mark(w.keyPrefix);
      } catch (_) {}
    }
    try {
      await _svc.updateByPrefix(
        keyPrefix: 'sync_status',
        title: 'Sync status',
        body: 'Updated ${DateTime.now().toLocal()}',
      );
    } catch (_) {}
  }

  Future<String?> _config(String provider) async {
    try {
      final store = await ref.read(widgetConfigStoreProvider.future);
      return store.get(provider);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshTasks() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final listId = await _config('PendingTasksWidgetProvider');
      final tasks = await repo.watchOpen(listId: listId).first;
      final titles = tasks.take(5).map((t) => t.title).toList();
      await _svc.update(
        keyPrefix: 'pending_tasks',
        provider: 'PendingTasksWidgetProvider',
        title: 'Pending tasks',
        body: titles.isEmpty ? 'No pending tasks.' : titles.join('\n'),
      );
      _mark('pending_tasks');
      _mark('pending_tasks_collection');
      await _svc.updateCollection(
        keyPrefix: 'pending_tasks_collection',
        provider: 'PendingTasksCollectionProvider',
        title: 'Pending tasks',
        items: tasks
            .take(5)
            .map((t) => {'id': t.id, 'title': t.title})
            .toList(),
      );
      _mark('pending_tasks_collection');
    } catch (_) {}
  }

  Future<void> _refreshCountdowns() async {
    try {
      final repo = ref.read(countdownRepositoryProvider);
      final all = await repo.watchCountdowns().first;
      final pinnedId = await _config('CountdownWidgetProvider');
      final items = pinnedId == null
          ? all
          : ([
              ...all.where((c) => c.id == pinnedId),
              ...all.where((c) => c.id != pinnedId),
            ]);
      if (items.isEmpty) {
        await _svc.updateByPrefix(
          keyPrefix: 'countdown',
          title: 'Countdown',
          body: 'No countdowns.',
        );
        return;
      }
      final next = items.first;
      final target = DateTime.tryParse(next.targetDate ?? '') ?? DateTime.now();
      final days = target.difference(DateTime.now()).inDays;
      await _svc.updateByPrefix(
        keyPrefix: 'countdown',
        title: next.title,
        body: '$days days remaining',
      );
      _mark('countdown');
      await _svc.updateCollection(
        keyPrefix: 'all_countdowns_collection',
        provider: 'CountdownsCollectionProvider',
        title: 'Countdowns',
        items: items.map((c) => {'id': c.id, 'title': c.title}).toList(),
      );
      _mark('all_countdowns_collection');
    } catch (_) {}
  }

  Future<void> _refreshHabits() async {
    try {
      final repo = ref.read(habitRepositoryProvider);
      final habits = await repo.watchHabits(archived: false).first;
      await _svc.updateByPrefix(
        keyPrefix: 'habits_today',
        title: 'Habits today',
        body: habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
      );
      _mark('habits_today');
      await _svc.updateCollection(
        keyPrefix: 'habits_today_collection',
        provider: 'HabitsTodayCollectionProvider',
        title: 'Habits today',
        items: habits.map((h) => {'id': h.id, 'title': h.name}).toList(),
      );
      _mark('habits_today_collection');
    } catch (_) {}
  }

  Future<void> _refreshNotes() async {
    try {
      final repo = ref.read(noteRepositoryProvider);
      final notes = await repo.watchNotesInFolder(null).first;
      final pinnedId =
          await _config('OneNoteWidgetProvider') ??
          await _config('PinnedNoteWidgetProvider');
      final shown = pinnedId == null
          ? (notes.isEmpty ? null : notes.first)
          : await repo.getNote(pinnedId);
      if (shown != null) {
        await _svc.update(
          keyPrefix: 'one_note',
          provider: 'OneNoteWidgetProvider',
          title: shown.title,
          body: (shown.body?.length ?? 0) > 120
              ? shown.body!.substring(0, 120)
              : shown.body ?? '',
        );
        _mark('one_note');
      }
      await _svc.updateCollection(
        keyPrefix: 'recent_notes_collection',
        provider: 'RecentNotesCollectionProvider',
        title: 'Recent notes',
        items: notes
            .take(5)
            .map((n) => {'id': n.id, 'title': n.title})
            .toList(),
      );
      _mark('recent_notes_collection');
    } catch (_) {}
  }

  Future<void> _refreshFocus() async {
    try {
      final repo = ref.read(focusRepositoryProvider);
      final session = await repo.currentSession();
      await _svc.updateByPrefix(
        keyPrefix: 'focus_timer',
        title: session == null ? 'Focus' : 'Focusing',
        body: session == null ? 'No active session.' : 'Session running',
      );
      _mark('focus_timer');
    } catch (_) {}
  }

  Future<void> _refreshEvents() async {
    try {
      final repo = ref.read(occurrenceRepositoryProvider);
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final occs = await repo.watchDay(key).first;
      final titles = occs.take(5).map((o) => o.title).toList();
      await _svc.updateCollection(
        keyPrefix: 'day_agenda_collection',
        provider: 'DayAgendaCollectionProvider',
        title: 'Today',
        items: occs
            .take(5)
            .map((o) => {'id': o.id, 'title': o.title})
            .toList()
            .cast<Map<String, String>>(),
      );
      _mark('day_agenda_collection');
      await _svc.updateByPrefix(
        keyPrefix: 'next_events',
        title: titles.isEmpty ? 'No events' : titles.first,
        body: titles.length > 1 ? titles.skip(1).join('\n') : '',
      );
      _mark('next_events');
    } catch (_) {}
  }

  /// Seven-day payload shared by the text push and the image renderer.
  Future<
    ({
      DateTime start,
      List<WeekCalendarDay> days,
      String title,
      String body,
      String dayKeys,
    })
  >
  _weekCalendarData() async {
    var firstDay = DateTime.monday;
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      firstDay = settings.weekStart;
    } catch (_) {}
    final now = DateTime.now();
    final start = weekStartFor(now, weekStartDay: firstDay);
    final end = start.add(const Duration(days: 7));
    final occs = await ref
        .read(occurrenceRepositoryProvider)
        .watchWindow(start, end)
        .first;
    final days = buildWeekCalendar(occurrences: occs, weekStart: start);
    return (
      start: start,
      days: days,
      title: weekCalendarTitle(start),
      body: weekCalendarBody(days),
      dayKeys: days.map((d) => dateKey(d.date)).join(','),
    );
  }

  Future<void> _refreshWeekCalendar() async {
    try {
      final data = await _weekCalendarData();
      await _svc.update(
        keyPrefix: 'week_calendar',
        provider: 'WeekCalendarWidgetProvider',
        title: data.title,
        body: data.body,
        extra: {'days': data.dayKeys},
      );
      _mark('week_calendar');
    } catch (_) {}
  }

  Future<void> _refreshMatrix() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final listId = await _config('MatrixWidgetProvider');
      final tasks = await repo.watchOpen(listId: listId).first;
      final counts = <String, int>{};
      for (final t in tasks) {
        counts[t.priority.toString()] =
            (counts[t.priority.toString()] ?? 0) + 1;
      }
      await _svc.updateByPrefix(
        keyPrefix: 'matrix',
        title: 'Matrix',
        body: counts.entries.map((e) => 'P${e.key}: ${e.value}').join(' '),
      );
      _mark('matrix');
      final matrixListId = listId;
      if (matrixListId == null) {
        await _svc.updateByPrefix(
          keyPrefix: 'matrix_counts',
          title: 'Matrix',
          body: counts.entries.map((e) => 'P${e.key}: ${e.value}').join(' '),
        );
        _mark('matrix_counts');
      }
    } catch (_) {}
  }

  Future<void> _refreshAlarms() async {
    try {
      final repo = ref.read(alarmRepositoryProvider);
      final upcoming = await repo.watchUpcoming().first;
      if (upcoming.isEmpty) {
        await _svc.updateByPrefix(
          keyPrefix: 'next_alarm',
          title: 'Alarm',
          body: 'No alarms.',
        );
        return;
      }
      final a = upcoming.first;
      await _svc.updateByPrefix(
        keyPrefix: 'next_alarm',
        title: a.title,
        body: 'Next alarm',
      );
      _mark('next_alarm');
    } catch (_) {}
  }

  Future<void> _refreshTaskVariants() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final tasks = await repo.watchOpen().first;
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final dueToday = tasks
          .where((t) => (t.dueDate ?? '') == todayKey)
          .toList();
      final overdue = tasks.where((t) {
        final d = t.dueDate;
        return d != null && d.compareTo(todayKey) < 0;
      }).toList();
      final inbox = tasks.where((t) => t.listId == null).toList();
      await _svc.updateByPrefix(
        keyPrefix: 'tasks_due_today',
        title: 'Due today',
        body: dueToday.isEmpty
            ? 'No tasks due today.'
            : dueToday.map((t) => t.title).join('\n'),
      );
      _mark('tasks_due_today');
      await _svc.updateByPrefix(
        keyPrefix: 'inbox_tasks',
        title: 'Inbox',
        body: inbox.isEmpty ? 'Inbox empty.' : '${inbox.length} tasks',
      );
      _mark('inbox_tasks');
      await _svc.updateByPrefix(
        keyPrefix: 'overdue_badge',
        title: 'Overdue',
        body: '${overdue.length}',
      );
      _mark('overdue_badge');
      await _svc.updateByPrefix(
        keyPrefix: 'task_counts',
        title: 'Tasks',
        body: 'Open: ${tasks.length}',
      );
      _mark('task_counts');
    } catch (_) {}
  }

  Future<void> _refreshDailySummary() async {
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final tasks = await taskRepo.watchOpen().first;
      final focusRepo = ref.read(focusRepositoryProvider);
      final minutes = await focusRepo.totalMinutes(
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      );
      await _svc.updateByPrefix(
        keyPrefix: 'daily_summary',
        title: 'Today',
        body: 'Open tasks: ${tasks.length}\nFocus: $minutes min',
      );
      _mark('daily_summary');
      await _svc.updateByPrefix(
        keyPrefix: 'focus_minutes',
        title: 'Focus',
        body: '$minutes min (24h)',
      );
      _mark('focus_minutes');
    } catch (_) {}
  }

  Future<void> _refreshSyncStatus() async {
    try {
      await _svc.updateByPrefix(
        keyPrefix: 'sync_status',
        title: 'Sync',
        body: 'Updated ${DateTime.now().toLocal()}',
      );
      _mark('sync_status');
    } catch (_) {}
  }

  Future<void> _refreshExtras() async {
    try {
      final alarmRepo = ref.read(alarmRepositoryProvider);
      final upcoming = await alarmRepo.watchUpcoming().first;
      await _svc.updateByPrefix(
        keyPrefix: 'alarm_status',
        title: 'Alarms',
        body: '${upcoming.length} upcoming',
      );
      _mark('alarm_status');
    } catch (_) {}
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final tags = await taskRepo.watchTags().first;
      await _svc.updateByPrefix(
        keyPrefix: 'tag_shortcuts',
        title: 'Tags',
        body: tags.isEmpty ? 'No tags.' : tags.map((t) => t.name).join(', '),
      );
      _mark('tag_shortcuts');
      final folders = await ref
          .read(noteRepositoryProvider)
          .watchChildFolders(null)
          .first;
      await _svc.updateByPrefix(
        keyPrefix: 'folder_shortcuts',
        title: 'Folders',
        body: folders.isEmpty
            ? 'No folders.'
            : folders.map((f) => f.name).join(', '),
      );
      _mark('folder_shortcuts');
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('last_backup_at');
      await _svc.updateByPrefix(
        keyPrefix: 'backup_status',
        title: 'Backup',
        body: last == null ? 'No backup yet.' : 'Last: $last',
      );
      _mark('backup_status');
    } catch (_) {}
    try {
      final occRepo = ref.read(occurrenceRepositoryProvider);
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final occs = await occRepo.watchDay(key).first;
      final current = occs.where((o) {
        final start = o.startUtc;
        return start <= now.millisecondsSinceEpoch &&
            o.endUtc >= now.millisecondsSinceEpoch;
      }).toList();
      await _svc.updateByPrefix(
        keyPrefix: 'free_busy',
        title: current.isEmpty ? 'Free' : 'Busy',
        body: current.isEmpty ? 'No current event.' : current.first.title,
      );
      _mark('free_busy');
      if (occs.isNotEmpty) {
        final nextMeeting = occs.firstWhere(
          (o) => o.startUtc > now.millisecondsSinceEpoch,
          orElse: () => occs.first,
        );
        await _svc.updateByPrefix(
          keyPrefix: 'next_meeting',
          title: nextMeeting.title,
          body: 'Next meeting',
        );
        _mark('next_meeting');
      }
    } catch (_) {}
  }

  /// Derives every remaining widget type from real app data so no pinned
  /// widget shows a generic placeholder. Toggles are only meaningful for
  /// tasks and habits; notes/countdowns/agenda collections intentionally
  /// hide the toggle button and open the app instead.
  Future<void> _refreshDerived() async {
    try {
      final now = DateTime.now();
      final monthName =
          'January February March April May June July August September October November December'
              .split(' ')[now.month - 1];
      final taskRepo = ref.read(taskRepositoryProvider);
      final tasks = await taskRepo.watchOpen().first;
      final titles = tasks.take(5).map((t) => t.title).toList();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final dueToday = tasks
          .where((t) => (t.dueDate ?? '') == todayKey)
          .toList();

      final occRepo = ref.read(occurrenceRepositoryProvider);
      final occs = await occRepo.watchDay(todayKey).first;
      final occTitles = occs.take(5).map((o) => o.title).toList();

      final habitRepo = ref.read(habitRepositoryProvider);
      final habits = await habitRepo.watchHabits(archived: false).first;

      final cdRepo = ref.read(countdownRepositoryProvider);
      final countdowns = await cdRepo.watchCountdowns().first;

      final noteRepo = ref.read(noteRepositoryProvider);
      final notes = await noteRepo.watchNotesInFolder(null).first;
      final noteTitles = notes.take(5).map((n) => n.title).toList();

      final focusRepo = ref.read(focusRepositoryProvider);
      final focusMin = await focusRepo.totalMinutes(
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );

      final counts = <String, int>{};
      for (final t in tasks) {
        final k = t.priority.toString();
        counts[k] = (counts[k] ?? 0) + 1;
      }
      final matrixBody = counts.entries
          .map((e) => 'P${e.key}: ${e.value}')
          .join(' ');

      // Tag-bound widget: filter open tasks by the configured tag name.
      var tagLabel = 'Tags';
      var tagTitles = titles;
      final tagName = await _config('TagTasksWidgetProvider');
      if (tagName != null) {
        tagLabel = '#$tagName';
        try {
          final tags = await taskRepo.watchTags().first;
          final match = tags.where((g) => g.name == tagName).toList();
          if (match.isNotEmpty) {
            final withTag = <String>[];
            for (final t in tasks.take(20)) {
              final ids = await taskRepo.taskTagIds(t.id);
              if (ids.contains(match.first.id)) withTag.add(t.title);
            }
            tagTitles = withTag.take(5).toList();
          }
        } catch (_) {}
      }

      // Smart-list widget: evaluate the bound smart list filter.
      var smartBody = 'Open: ${tasks.length}, due today: ${dueToday.length}';
      final smartId = await _config('SmartListWidgetProvider');
      if (smartId != null) {
        try {
          final smartLists = await taskRepo.watchSmartLists().first;
          final match = smartLists.where((s) => s.id == smartId).toList();
          if (match.isNotEmpty) {
            final rows = await taskRepo.evalSmartList(
              Map<String, Object?>.from(
                jsonDecode(match.first.filterJson) as Map,
              ),
            );
            smartBody = '${match.first.name}: ${rows.length} tasks';
          }
        } catch (_) {}
      }

      var subtaskBody = 'No subtasks.';
      final subtaskParentId = await _config('SubtaskProgressWidgetProvider');
      final subtaskParent = subtaskParentId != null
          ? tasks.where((t) => t.id == subtaskParentId).toList()
          : tasks;
      if (subtaskParent.isNotEmpty) {
        try {
          final progress = await taskRepo.subtaskProgress(
            subtaskParent.first.id,
          );
          subtaskBody =
              '${subtaskParent.first.title}: ${progress[0]}/${progress[1]} done';
        } catch (_) {}
      }

      var streakBody = 'No habits.';
      final streakHabitId = await _config('HabitStreakWidgetProvider');
      final streakHabit = streakHabitId != null
          ? habits.where((h) => h.id == streakHabitId).toList()
          : habits;
      if (streakHabit.isNotEmpty) {
        try {
          final today = habitDateKey(DateTime.now());
          final log = await habitRepo.logFor(streakHabit.first.id, today);
          streakBody =
              '${streakHabit.first.name}: ${log != null ? 'done today' : 'not done today'}';
        } catch (_) {
          streakBody = '${streakHabit.first.name} tracked';
        }
      }

      var pinnedTitle = notes.isEmpty ? 'Note' : notes.first.title;
      var pinnedBody = notes.isEmpty ? 'No notes.' : noteTitles.join('\n');
      final pinnedNoteId =
          await _config('PinnedNoteWidgetProvider') ??
          await _config('OneNoteWidgetProvider');
      if (pinnedNoteId != null) {
        try {
          final n = await noteRepo.getNote(pinnedNoteId);
          if (n != null) {
            pinnedTitle = n.title;
            pinnedBody = n.body ?? '';
          }
        } catch (_) {}
      }

      var powerBody = 'Battery-aware sync on';
      try {
        final low = await PowerSavingManager.instance.isLowBattery;
        powerBody = low ? 'Low battery, sync slowed' : 'OK';
      } catch (_) {}

      var daysSinceBody = 'No past dates.';
      final past = countdowns.where((c) {
        final t = DateTime.tryParse(c.targetDate ?? '');
        return t != null && t.isBefore(now);
      }).toList();
      if (past.isNotEmpty) {
        final t = DateTime.tryParse(past.first.targetDate ?? '') ?? now;
        daysSinceBody =
            '${past.first.title}: ${now.difference(t).inDays} days ago';
      }

      final derived = <String, Map<String, String>>{
        'month_calendar': {
          'title': '$monthName ${now.year}',
          'body': occTitles.isEmpty ? 'No events today.' : occTitles.join('\n'),
        },
        'week_calendar': {
          'title': 'This week',
          'body': 'Open ephemeron for details.',
        },
        'day_agenda': {
          'title': 'Today',
          'body': occTitles.isEmpty ? 'No events.' : occTitles.join('\n'),
        },
        'smart_list': {'title': 'Smart list', 'body': smartBody},
        'tag_tasks': {
          'title': tagLabel,
          'body': tagTitles.isEmpty ? 'No tasks.' : tagTitles.join('\n'),
        },
        'subtask_progress': {'title': 'Subtasks', 'body': subtaskBody},
        'matrix_counts': {
          'title': 'Matrix',
          'body': matrixBody.isEmpty ? 'No tasks.' : matrixBody,
        },
        'habit_streak': {'title': 'Streaks', 'body': streakBody},
        'habit_completion_rate': {'title': 'Completion', 'body': streakBody},
        'habit_heatmap': {'title': 'Heatmap', 'body': streakBody},
        'pomodoro': {'title': 'Focus', 'body': '$focusMin min (24h)'},
        'pinned_note': {'title': pinnedTitle, 'body': pinnedBody},
        'recent_notes': {
          'title': 'Notes',
          'body': noteTitles.isEmpty ? 'No notes.' : noteTitles.join('\n'),
        },
        'quick_capture': {
          'title': 'Capture',
          'body': 'New task / event / focus / note',
        },
        'all_countdowns': {
          'title': 'Countdowns',
          'body': countdowns.isEmpty
              ? 'No countdowns.'
              : countdowns.map((c) => c.title).join('\n'),
        },
        'days_since': {'title': 'Days since', 'body': daysSinceBody},
        'quick_actions': {
          'title': 'Actions',
          'body': 'New task / event / focus / note',
        },
        'search_widget': {
          'title': 'Search',
          'body': 'Search tasks, notes, events',
        },
        'weekly_chart': {
          'title': 'Week',
          'body': 'Focus $focusMin min (24h), ${tasks.length} open',
        },
        'power_status': {'title': 'Battery', 'body': powerBody},
        // No vacation feature exists in the app; report honestly instead of
        // implying live state.
        'vacation_status': {
          'title': 'Vacation',
          'body': 'Not available in this version',
        },
      };
      for (final e in derived.entries) {
        if (_touched.contains(e.key)) continue;
        try {
          await _svc.updateByPrefix(
            keyPrefix: e.key,
            title: e.value['title'],
            body: e.value['body'],
          );
          _mark(e.key);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Renders image widgets only when a matching widget is pinned (when the
  /// platform reports installed widgets) and at most every 15 minutes per
  /// image. Falls back to the throttle when the installed list is
  /// unavailable so images still refresh on platforms without the API.
  /// No-op on platforms without a widget host.
  Future<void> _refreshImages() async {
    if (!isHomeWidgetSupported) return;
    final images = WidgetImageService();
    Set<String>? installed;
    try {
      final all = await HomeWidget.getInstalledWidgets();
      installed = {for (final w in all) w.androidClassName ?? ''};
    } catch (_) {}
    bool want(String provider) {
      if (installed == null) return true;
      return installed.any((c) => widgetProviderMatches(c, provider));
    }

    Future<bool> due(String key) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getInt('widget_image_last_$key');
        final ok = WidgetImageService.shouldRender(
          lastMs: last,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (ok) {
          await prefs.setInt(
            'widget_image_last_$key',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        return ok;
      } catch (_) {
        return true;
      }
    }

    if (want('WeekCalendarWidgetProvider') && await due('week_calendar')) {
      try {
        final data = await _weekCalendarData();
        final path = await images.renderWeekCalendar(
          days: data.days,
          now: DateTime.now(),
        );
        if (path != null) {
          await _svc.update(
            keyPrefix: 'week_calendar',
            provider: 'WeekCalendarWidgetProvider',
            title: data.title,
            body: data.body,
            imagePath: path,
            extra: {'days': data.dayKeys},
          );
        }
      } catch (_) {}
    }
    if (want('MonthCalendarWidgetProvider') && await due('month_calendar')) {
      try {
        final now = DateTime.now();
        final from = DateTime(now.year, now.month, 1);
        final to = DateTime(now.year, now.month + 1, 0);
        final occs = await ref
            .read(occurrenceRepositoryProvider)
            .watchWindow(from, to)
            .first;
        final days = <int>{};
        for (final o in occs) {
          final start = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
          if (start.year == now.year && start.month == now.month) {
            days.add(start.day);
          }
        }
        final path = await images.renderMonthGrid(
          year: now.year,
          month: now.month,
          eventDays: days,
          today: now.day,
        );
        if (path != null) {
          await _svc.updateByPrefix(
            keyPrefix: 'month_calendar',
            title: 'Calendar',
            body: days.isEmpty ? 'No events.' : '${days.length} days',
            imagePath: path,
          );
        }
      } catch (_) {}
    }
    if (want('HabitHeatmapWidgetProvider') && await due('habit_heatmap')) {
      try {
        final repo = ref.read(habitRepositoryProvider);
        final habits = await repo.watchHabits(archived: false).first;
        final pinnedHeatId = await _config('HabitStreakWidgetProvider');
        final heatHabit = pinnedHeatId == null
            ? (habits.isEmpty ? null : habits.first)
            : (habits.any((h) => h.id == pinnedHeatId)
                  ? habits.firstWhere((h) => h.id == pinnedHeatId)
                  : (habits.isEmpty ? null : habits.first));
        if (heatHabit != null) {
          final logs = await repo.watchLogs(heatHabit.id).first;
          final done = {
            for (final l in logs)
              if (l.done) l.dayKey,
          };
          final path = await images.renderHeatmap(
            done: done,
            end: DateTime.now(),
          );
          if (path != null) {
            await _svc.updateByPrefix(
              keyPrefix: 'habit_heatmap',
              title: 'Heatmap',
              body: heatHabit.name,
              imagePath: path,
            );
          }
        }
      } catch (_) {}
    }
    if (want('WeeklyChartWidgetProvider') && await due('weekly_chart')) {
      try {
        final repo = ref.read(focusRepositoryProvider);
        final now = DateTime.now();
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        final minutes = <int>[];
        for (var i = 0; i < 7; i++) {
          final day = start.add(Duration(days: i));
          final next = day.add(const Duration(days: 1));
          minutes.add(
            await repo.totalMinutes(
              day.millisecondsSinceEpoch,
              next.millisecondsSinceEpoch,
            ),
          );
        }
        final path = await images.renderWeekBars(minutes: minutes);
        if (path != null) {
          await _svc.updateByPrefix(
            keyPrefix: 'weekly_chart',
            title: 'Week',
            body: 'Focus ${minutes.reduce((a, b) => a + b)} min',
            imagePath: path,
          );
        }
      } catch (_) {}
    }
  }
}

final homeWidgetDataBinderProvider = Provider<HomeWidgetDataBinder>((ref) {
  return HomeWidgetDataBinder(ref);
});
