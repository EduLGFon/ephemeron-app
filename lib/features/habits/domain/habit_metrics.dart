/// Computed, not stored — derived fresh from HabitLogs whenever
/// requested. MVP scope per the build-order cut: current streak + a
/// 7-day strip. The brainstorm's full month heatmap is Phase 2.
class HabitMetrics {
  const HabitMetrics({
    required this.currentStreak,
    required this.longestStreak,
    required this.last7Days,
  });

  final int currentStreak;
  final int longestStreak;

  /// Oldest-to-newest, always exactly 7 entries (today last). Only
  /// meaningful (true/false) for days the habit was actually due — a
  /// day the habit wasn't due on is neither a completion nor a miss, and
  /// callers should render those distinctly (e.g. greyed out) rather
  /// than as a red "missed" mark.
  final List<HabitDayStatus> last7Days;
}

enum HabitDayStatus { completed, missed, notDue, future }
