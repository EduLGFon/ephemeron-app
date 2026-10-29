// Riverpod providers for focus. UI reads only from Drift streams;
// the running session is a Future invalidated on start/finish.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/focus_repository.dart';
import '../../../data/repositories/habit_repository.dart';
import '../../../data/repositories/task_repository.dart';

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  return FocusRepository(ref.watch(appDatabaseProvider));
});

final currentFocusSessionProvider = FutureProvider<FocusSession?>((ref) {
  return ref.watch(focusRepositoryProvider).currentSession();
});

final recentFocusSessionsProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusRepositoryProvider).watchRecent();
});

int _dayStartUtc(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch;

final focusTodayMinutesProvider = FutureProvider<int>((ref) {
  final now = DateTime.now().toUtc();
  return ref
      .watch(focusRepositoryProvider)
      .totalMinutes(_dayStartUtc(now), now.millisecondsSinceEpoch + 60000);
});

/// Minutes per day for the last 7 days, oldest first.
final focusWeekMinutesProvider = FutureProvider<List<int>>((ref) async {
  final repo = ref.watch(focusRepositoryProvider);
  final now = DateTime.now().toUtc();
  final out = <int>[];
  for (var i = 6; i >= 0; i--) {
    final day = now.subtract(Duration(days: i));
    final start = _dayStartUtc(day);
    out.add(await repo.totalMinutes(start, start + 86400000));
  }
  return out;
});

/// Open tasks linkable to a session.
final linkableTasksProvider = StreamProvider<List<Task>>((ref) {
  return TaskRepository(ref.watch(appDatabaseProvider)).watchOpen();
});

/// Active habits linkable to a session.
final linkableHabitsProvider = StreamProvider<List<Habit>>((ref) {
  return HabitRepository(
    ref.watch(appDatabaseProvider),
  ).watchHabits(archived: false);
});
