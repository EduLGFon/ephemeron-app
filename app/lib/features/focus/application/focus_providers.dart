import 'package:ephemeron/core/time/time.dart';
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
      .totalMinutes(
        _dayStartUtc(now),
        now.millisecondsSinceEpoch + msPerMinute,
      );
});

/// Minutes per day for the last 7 days, oldest first.
final focusWeekMinutesProvider = FutureProvider<List<int>>((ref) async {
  final repo = ref.watch(focusRepositoryProvider);
  final now = DateTime.now().toUtc();
  final out = <int>[];
  for (var i = 6; i >= 0; i--) {
    final day = now.subtract(Duration(days: i));
    final start = _dayStartUtc(day);
    out.add(await repo.totalMinutes(start, start + msPerDay));
  }
  return out;
});

/// Minutes per day for [year]/[month], index 0 = day 1.
final focusMonthMinutesProvider = FutureProvider.family<List<int>, DateTime>((
  ref,
  month,
) async {
  final repo = ref.watch(focusRepositoryProvider);
  final daysInMonth = DateTime.utc(month.year, month.month + 1, 0).day;
  final out = List<int>.filled(daysInMonth, 0);
  final from = DateTime.utc(month.year, month.month, 1).millisecondsSinceEpoch;
  final to = DateTime.utc(
    month.year,
    month.month + 1,
    1,
  ).millisecondsSinceEpoch;
  final sessions = await repo.sessionsInRange(from, to);
  for (final s in sessions) {
    final end = s.endUtc ?? to;
    final start = s.startUtc.clamp(from, to);
    final clampedEnd = end.clamp(from, to);
    if (clampedEnd <= start) continue;
    // Attribute clipped minutes to the start day (simple, documented).
    final day = DateTime.fromMillisecondsSinceEpoch(start, isUtc: true).day;
    out[day - 1] += ((clampedEnd - start) / msPerMinute).floor();
  }
  return out;
});

/// Focused minutes grouped by a session key in the last 30 days.
/// Returns entries of (label, minutes) sorted desc, capped to 8 rows.
Future<List<(String, int)>> _groupMinutes(
  FocusRepository repo,
  String? Function(FocusSession s) keyOf,
  Map<String, String> labels,
  String fallback,
) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final from = now - 30 * msPerDay;
  final sessions = await repo.sessionsInRange(from, now);
  final totals = <String, int>{};
  for (final s in sessions) {
    final end = s.endUtc ?? now;
    if (end <= s.startUtc) continue;
    final key = keyOf(s) ?? fallback;
    totals[key] =
        (totals[key] ?? 0) + ((end - s.startUtc) / msPerMinute).floor();
  }
  final rows = [
    for (final e in totals.entries) (labels[e.key] ?? e.key, e.value),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return rows.take(8).toList();
}

final focusStatsByTaskProvider = FutureProvider<List<(String, int)>>((
  ref,
) async {
  final repo = ref.watch(focusRepositoryProvider);
  final tasks = await ref.watch(linkableTasksProvider.future);
  final labels = {for (final t in tasks) t.id: t.title};
  return _groupMinutes(repo, (s) => s.taskId, labels, '(no task)');
});

final focusStatsByHabitProvider = FutureProvider<List<(String, int)>>((
  ref,
) async {
  final repo = ref.watch(focusRepositoryProvider);
  final habits = await ref.watch(linkableHabitsProvider.future);
  final labels = {for (final h in habits) h.id: h.name};
  return _groupMinutes(repo, (s) => s.habitId, labels, '(no habit)');
});

/// Minutes by time of day (local hour): morning 5-12, afternoon 12-18,
/// evening 18-23, night 23-5. Last 30 days.
final focusStatsByTimeOfDayProvider = FutureProvider<List<(String, int)>>((
  ref,
) async {
  final repo = ref.watch(focusRepositoryProvider);
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final sessions = await repo.sessionsInRange(now - 30 * msPerDay, now);
  final totals = <String, int>{
    'Morning': 0,
    'Afternoon': 0,
    'Evening': 0,
    'Night': 0,
  };
  for (final s in sessions) {
    final end = s.endUtc ?? now;
    if (end <= s.startUtc) continue;
    final hour = DateTime.fromMillisecondsSinceEpoch(s.startUtc).toLocal().hour;
    final bucket = hour >= 5 && hour < 12
        ? 'Morning'
        : hour >= 12 && hour < 18
        ? 'Afternoon'
        : hour >= 18 && hour < 23
        ? 'Evening'
        : 'Night';
    totals[bucket] =
        totals[bucket]! + ((end - s.startUtc) / msPerMinute).floor();
  }
  return totals.entries.map((e) => (e.key, e.value)).toList();
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
