import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../features/tasks/application/tasks_providers.dart';
import '../../../features/countdowns/application/countdowns_providers.dart';
import '../../../features/habits/application/habits_providers.dart';
import '../../../features/notes/application/notes_providers.dart';
import '../../../features/focus/application/focus_providers.dart';
import '../../../features/calendar/application/calendar_providers.dart';
import '../../../features/alarms/application/alarm_providers.dart';import 'home_widget_service.dart';

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
      _refreshMatrix(),
      _refreshAlarms(),
      _refreshTaskVariants(),
      _refreshDailySummary(),
      _refreshSyncStatus(),
      _refreshExtras(),
      _refreshDerived(),
    ]);
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

  Future<void> _refreshTasks() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final tasks = await repo.watchOpen().first;
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
      final items = await repo.watchCountdowns().first;
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
      await _svc.updateByPrefix(        keyPrefix: 'countdown',
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
      if (notes.isNotEmpty) {
        await _svc.update(
          keyPrefix: 'one_note',
          provider: 'OneNoteWidgetProvider',
          title: notes.first.title,
          body: (notes.first.body?.length ?? 0) > 120
              ? notes.first.body!.substring(0, 120)
              : notes.first.body ?? '',        );
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
        body: session == null
            ? 'No active session.'
            : 'Session running',
      );
      _mark('focus_timer');
    } catch (_) {}
  }

  Future<void> _refreshEvents() async {
    try {
      final repo = ref.read(occurrenceRepositoryProvider);
      final now = DateTime.now();
      final key = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
            .cast<Map<String, String>>(),      );
      _mark('day_agenda_collection');      await _svc.updateByPrefix(
        keyPrefix: 'next_events',
        title: titles.isEmpty ? 'No events' : titles.first,
        body: titles.length > 1 ? titles.skip(1).join('\n') : '',
      );
      _mark('next_events');
    } catch (_) {}
  }

  Future<void> _refreshMatrix() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final tasks = await repo.watchOpen().first;
      final counts = <String, int>{};
      for (final t in tasks) {
        counts[t.priority.toString()] = (counts[t.priority.toString()] ?? 0) + 1;
      }
      await _svc.updateByPrefix(
        keyPrefix: 'matrix',
        title: 'Matrix',
        body: 'Open tasks: ${tasks.length}',
      );
      _mark('matrix');
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
      final dueToday = tasks.where((t) => (t.dueDate ?? '') == todayKey).toList();
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
      final folders = await ref.read(noteRepositoryProvider).watchChildFolders(null).first;
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
      final dueToday =
          tasks.where((t) => (t.dueDate ?? '') == todayKey).toList();

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
      final matrixBody = counts.entries.map((e) => 'P${e.key}: ${e.value}').join(' ');

      var subtaskBody = 'No subtasks.';
      if (tasks.isNotEmpty) {
        try {
          final subs = await taskRepo.watchSubtasks(tasks.first.id).first;
          final done = subs.where((s) => s.completedAt != null).length;
          subtaskBody = '${tasks.first.title}: $done/${subs.length} done';
        } catch (_) {}
      }

      var streakBody = 'No habits.';
      if (habits.isNotEmpty) {
        streakBody = '${habits.length} habits tracked';
      }

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
          'body': occTitles.isEmpty
              ? 'No events today.'
              : occTitles.join('\n'),
        },
        'week_calendar': {
          'title': 'This week',
          'body': occTitles.isEmpty
              ? 'No events today.'
              : occTitles.join('\n'),
        },
        'day_agenda': {
          'title': 'Today',
          'body': occTitles.isEmpty ? 'No events.' : occTitles.join('\n'),
        },
        'smart_list': {
          'title': 'Today',
          'body': 'Open: ${tasks.length}, due today: ${dueToday.length}',
        },
        'tag_tasks': {
          'title': 'Tags',
          'body': titles.isEmpty ? 'No tasks.' : titles.join('\n'),
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
        'pinned_note': {
          'title': notes.isEmpty ? 'Note' : notes.first.title,
          'body': notes.isEmpty ? 'No notes.' : noteTitles.join('\n'),
        },
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
        'power_status': {
          'title': 'Battery',
          'body': 'Battery-aware sync on',
        },
        'vacation_status': {'title': 'Vacation', 'body': 'Off'},
      };
      for (final e in derived.entries) {
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
}

final homeWidgetDataBinderProvider = Provider<HomeWidgetDataBinder>((ref) {
  return HomeWidgetDataBinder(ref);
});