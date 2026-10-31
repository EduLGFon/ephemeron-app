// Shared headless widget payload builders. Used both by the WorkManager
// background sync and by the widget toggle callback so a tap is reflected
// without opening the app. No Riverpod: everything runs off [db] directly.
import 'package:home_widget/home_widget.dart';

import '../drift/app_database.dart';
import '../repositories/countdown_repository.dart';
import '../repositories/focus_repository.dart';
import '../repositories/habit_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/task_repository.dart';

Future<void> _push(
  String prefix,
  String provider,
  String title,
  String body,
) async {
  try {
    await HomeWidget.saveWidgetData<String>('${prefix}_title', title);
    await HomeWidget.saveWidgetData<String>('${prefix}_body', body);
    await HomeWidget.updateWidget(
      androidName: provider,
      qualifiedAndroidName: 'com.spotnik.ephemeron.$provider',
    );
  } catch (_) {}
}

/// Re-reads open tasks and pushes task widgets. Honors an optional
/// list-id filter stored under widget_config_<provider>.
Future<void> pushTaskWidgets(AppDatabase db, {String? listId}) async {
  try {
    final tasks =
        await TaskRepository(db).watchOpen(listId: listId).first;
    final titles = tasks.take(5).map((t) => t.title).toList();
    await _push(
      'pending_tasks',
      'PendingTasksWidgetProvider',
      'Pending tasks',
      titles.isEmpty ? 'No pending tasks.' : titles.join('\n'),
    );
    try {
      final items = tasks
          .take(5)
          .map(
            (t) => '{"id":"${t.id}","title":"${t.title.replaceAll('"', '')}"}',
          )
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_title',
        'Pending tasks',
      );
      await HomeWidget.updateWidget(
        androidName: 'PendingTasksCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.PendingTasksCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
}

/// Re-reads habits and pushes habit widgets.
Future<void> pushHabitWidgets(AppDatabase db) async {
  try {
    final habits =
        await HabitRepository(db).watchHabits(archived: false).first;
    await _push(
      'habits_today',
      'HabitsTodayWidgetProvider',
      'Habits today',
      habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
    );
    try {
      final items = habits
          .map((h) => '{"id":"${h.id}","title":"${h.name.replaceAll('"', '')}"}')
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'habits_today_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'habits_today_collection_title',
        'Habits today',
      );
      await HomeWidget.updateWidget(
        androidName: 'HabitsTodayCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.HabitsTodayCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
}

Future<void> pushCountdownWidgets(AppDatabase db) async {
  try {
    final items = await CountdownRepository(db).watchCountdowns().first;
    if (items.isEmpty) return;
    final next = items.first;
    final target = DateTime.tryParse(next.targetDate ?? '') ?? DateTime.now();
    final days = target.difference(DateTime.now()).inDays;
    await _push(
      'countdown',
      'CountdownWidgetProvider',
      next.title,
      '$days days remaining',
    );
  } catch (_) {}
}

Future<void> pushNoteWidgets(AppDatabase db) async {
  try {
    final notes = await NoteRepository(db).watchNotesInFolder(null).first;
    if (notes.isEmpty) return;
    final body = notes.first.body ?? '';
    await _push(
      'one_note',
      'OneNoteWidgetProvider',
      notes.first.title,
      body.length > 120 ? body.substring(0, 120) : body,
    );
  } catch (_) {}
}

Future<void> pushFocusWidgets(AppDatabase db) async {
  try {
    final session = await FocusRepository(db).currentSession();
    await _push(
      'focus_timer',
      'FocusTimerWidgetProvider',
      session == null ? 'Focus' : 'Focusing',
      session == null ? 'No active session.' : 'Session running',
    );
  } catch (_) {}
}

/// Pushes every widget type a headless isolate can compute: tasks, habits,
// countdowns, notes, focus, plus today's agenda from the occurrence cache
// and derived summaries. Mirrors the foreground binder's key names.
Future<void> pushAllHeadlessWidgets(AppDatabase db) async {
  await pushTaskWidgets(db);
  await pushHabitWidgets(db);
  await pushCountdownWidgets(db);
  await pushNoteWidgets(db);
  await pushFocusWidgets(db);
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
          .map((o) => '{"id":"${o.id}","title":"${(o.title ?? '').replaceAll('"', '')}"}')
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
