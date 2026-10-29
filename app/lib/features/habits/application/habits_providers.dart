// Riverpod providers for habits. UI reads only from Drift streams
// (streaks derive from the logs stream input via the repository).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/habit_repository.dart';
import '../../../domain/habits/date_key.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(ref.watch(appDatabaseProvider));
});

String habitTodayKey() => habitDateKey(DateTime.now());

final habitSectionsProvider = StreamProvider<List<HabitSection>>((ref) {
  return ref.watch(habitRepositoryProvider).watchSections();
});

final habitsProvider = StreamProvider.family<List<Habit>, bool>((
  ref,
  archived,
) {
  return ref.watch(habitRepositoryProvider).watchHabits(archived: archived);
});

final habitLogsProvider = StreamProvider.family<List<HabitLog>, String>((
  ref,
  habitId,
) {
  return ref.watch(habitRepositoryProvider).watchLogs(habitId);
});

final habitStreakProvider =
    FutureProvider.family<({int current, int best}), String>((ref, habitId) {
      return ref
          .watch(habitRepositoryProvider)
          .streaks(habitId, habitTodayKey());
    });

/// Day the habit list acts on (backfill past days). Defaults to today.
final selectedHabitDayProvider = NotifierProvider<SelectedHabitDay, String>(
  SelectedHabitDay.new,
);

class SelectedHabitDay extends Notifier<String> {
  @override
  String build() => habitTodayKey();

  void select(String day) => state = day;
}

final showArchivedHabitsProvider = NotifierProvider<ShowArchivedHabits, bool>(
  ShowArchivedHabits.new,
);

class ShowArchivedHabits extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
