part of '../headless_widget_push.dart';

/// Pushes every widget type a headless isolate can compute: tasks, habits,
/// countdowns, notes, focus, plus today's agenda from the occurrence cache
/// and derived summaries. Mirrors the foreground binder's key names.
Future<void> pushAllHeadlessWidgets(AppDatabase db) async {
  final listId = await readWidgetBinding('PendingTasksWidgetProvider');
  final noteId =
      await readWidgetBinding('OneNoteWidgetProvider') ??
      await readWidgetBinding('PinnedNoteWidgetProvider');
  final countdownId = await readWidgetBinding('CountdownWidgetProvider');
  await pushTaskWidgets(db, listId: listId);
  await pushHabitWidgets(db);
  await pushCountdownWidgets(db, pinnedId: countdownId);
  await pushNoteWidgets(db, noteId: noteId);
  await pushFocusWidgets(db);
  await rebuildOccurrenceWindowHeadless(db);
  try {
    final prefs = await SharedPreferences.getInstance();
    final firstDay = prefs.getInt('calendar.weekStart') ?? DateTime.monday;
    final now = DateTime.now();
    final start = weekStartFor(now, weekStartDay: firstDay);
    final end = start.add(const Duration(days: 7));
    final occs =
        await (db.select(db.occurrenceCache)..where(
              (o) =>
                  o.startUtc.isSmallerOrEqualValue(end.millisecondsSinceEpoch) &
                  o.endUtc.isBiggerOrEqualValue(start.millisecondsSinceEpoch),
            ))
            .get();
    final days = buildWeekCalendar(occurrences: occs, weekStart: start);
    final theme = prefs.getString('week_calendar_theme') ?? 'light';
    await _push(
      'week_calendar',
      'WeekCalendarWidgetProvider',
      weekCalendarTitle(start),
      weekCalendarBody(days),
      extra: {
        'days': days.map((d) => dateKey(d.date)).join(','),
        'theme': theme,
      },
    );
  } catch (_) {}
  try {
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final occs = await (db.select(
      db.occurrenceCache,
    )..where((o) => o.dayKey.equals(key))).get();
    final titles = occs.take(5).map((o) => o.title ?? '').toList();
    await _push(
      'next_events',
      'NextEventsWidgetProvider',
      titles.isEmpty ? 'No events' : titles.first,
      titles.length > 1 ? titles.skip(1).join('\n') : '',
    );
    try {
      final items = occs
          .take(5)
          .map(
            (o) =>
                '{"id":"${o.id}","title":"${(o.title ?? '').replaceAll('"', '')}"}',
          )
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'day_agenda_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'day_agenda_collection_title',
        'Today',
      );
      await HomeWidget.updateWidget(
        androidName: 'DayAgendaCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.DayAgendaCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
  try {
    final tasks = await TaskRepository(db).watchOpen().first;
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final overdue = tasks.where((t) {
      final d = t.dueDate;
      return d != null && d.compareTo(todayKey) < 0;
    }).length;
    await _push(
      'overdue_badge',
      'OverdueBadgeWidgetProvider',
      'Overdue',
      '$overdue',
    );
    await _push(
      'task_counts',
      'TaskCountsWidgetProvider',
      'Tasks',
      'Open: ${tasks.length}',
    );
  } catch (_) {}
  await _push(
    'sync_status',
    'SyncStatusWidgetProvider',
    'Synced',
    'Updated ${DateTime.now().toLocal()}',
  );
}
