import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/tasks/application/tasks_providers.dart';
import '../../../features/countdowns/application/countdowns_providers.dart';
import '../../../features/habits/application/habits_providers.dart';
import '../../../features/notes/application/notes_providers.dart';
import '../../../features/focus/application/focus_providers.dart';
import 'home_widget_service.dart';

class HomeWidgetDataBinder {
  HomeWidgetDataBinder(this.ref);
  final Ref ref;

  HomeWidgetService get _svc => ref.read(homeWidgetServiceProvider);

  Future<void> refreshAll() async {
    await Future.wait([
      _refreshTasks(),
      _refreshCountdowns(),
      _refreshHabits(),
      _refreshNotes(),
      _refreshFocus(),
    ]);
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
      await _svc.updateCollection(
        keyPrefix: 'pending_tasks_collection',
        provider: 'PendingTasksCollectionProvider',
        title: 'Pending tasks',
        items: tasks
            .take(5)
            .map((t) => {'id': t.id, 'title': t.title})
            .toList(),
      );
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
      await _svc.updateCollection(
        keyPrefix: 'all_countdowns_collection',
        provider: 'CountdownsCollectionProvider',
        title: 'Countdowns',
        items: items.map((c) => {'id': c.id, 'title': c.title}).toList(),
      );
    } catch (_) {}
  }

  Future<void> _refreshHabits() async {
    try {
      final repo = ref.read(habitRepositoryProvider);
      final habits = await repo.watchHabits(archived: false).first;      await _svc.updateByPrefix(
        keyPrefix: 'habits_today',
        title: 'Habits today',
        body: habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
      );
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
    } catch (_) {}
  }
}

final homeWidgetDataBinderProvider = Provider<HomeWidgetDataBinder>((ref) {
  return HomeWidgetDataBinder(ref);
});