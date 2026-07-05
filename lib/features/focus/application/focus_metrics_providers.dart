import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'focus_repository_provider.dart';

/// Bumped after every completed session so the metrics providers below
/// know to refetch — FocusRepository's totals are plain Future-returning
/// queries, not reactive streams (aggregating a table on every write
/// would be overkill for something checked this infrequently), so this
/// is the simple manual invalidation trigger instead.
final focusMetricsRefreshProvider = StateProvider<int>((ref) => 0);

final totalFocusedTodayProvider = FutureProvider<Duration>((ref) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).totalFocusedToday();
});

final totalFocusedThisWeekProvider = FutureProvider<Duration>((ref) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).totalFocusedThisWeek();
});

final monthlyFocusTotalsProvider = FutureProvider.family<Map<DateTime, Duration>, DateTime>((ref, month) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).dailyTotalsForMonth(month);
});

final totalFocusedThisMonthProvider = FutureProvider.family<Duration, DateTime>((ref, month) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).totalFocusedThisMonth(month);
});

final totalFocusedThisYearProvider = FutureProvider.family<Duration, int>((ref, year) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).totalFocusedThisYear(year);
});

final totalFocusedAllTimeProvider = FutureProvider<Duration>((ref) {
  ref.watch(focusMetricsRefreshProvider);
  return ref.watch(focusRepositoryProvider).totalFocusedAllTime();
});
