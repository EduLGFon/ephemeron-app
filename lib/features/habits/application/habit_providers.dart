import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../domain/habit_metrics.dart';
import '../data/habit_repository.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(alarmSchedulerProvider),
  );
});

final habitsProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchHabits();
});

final habitLogsProvider = StreamProvider.family<List<HabitLog>, String>((
  ref,
  habitId,
) {
  return ref.watch(habitRepositoryProvider).watchLogs(habitId);
});

/// Recomputed whenever the habit's logs change — metrics aren't stored,
/// they're derived, so this just needs to re-run after any log write.
final habitMetricsProvider = FutureProvider.family<HabitMetrics, Habit>((
  ref,
  habit,
) async {
  // Watching (not just reading) the logs stream is what makes this
  // provider re-run automatically when logProgress()/toggleBinaryToday()
  // write a new log — without this, the metrics would go stale until
  // something else happened to trigger a rebuild.
  ref.watch(habitLogsProvider(habit.id));
  return ref.watch(habitRepositoryProvider).computeMetrics(habit);
});

/// Kicks off the weekly/interval one-shot alarm catch-up described in
/// HabitRepository.refreshOneShotAlarms's doc comment. Call once at
/// startup alongside the other *InitProvider watches in main.dart.
///
/// Explicitly waits on [alarmSchedulerInitProvider] first — without
/// this, it could race ahead of AlarmScheduler's own channel/timezone
/// setup and fail to schedule anything on a cold start.
final habitAlarmsRefreshProvider = FutureProvider<void>((ref) async {
  await ref.watch(alarmSchedulerInitProvider.future);
  await ref.watch(habitRepositoryProvider).refreshOneShotAlarms();
});
