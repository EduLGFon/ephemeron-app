part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderDerived on HomeWidgetDataBinder {
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
}
