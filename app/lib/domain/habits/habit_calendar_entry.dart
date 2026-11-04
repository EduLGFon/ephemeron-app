// Lightweight view of a scheduled habit for a single calendar day.

/// Parses the stored `HH:mm` reminder time into local minutes since midnight.
/// Invalid or empty values return null, so the habit falls back to all-day.
int? parseHabitTimeMinutes(String? reminderTime) {
  if (reminderTime == null) return null;
  final parts = reminderTime.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

class HabitCalendarEntry {
  const HabitCalendarEntry({
    required this.habitId,
    required this.habitName,
    required this.dayKey,
    this.timeMinutes,
    this.unit,
    this.goalAmount,
    this.increment,
    this.amount = 0,
    this.done = false,
    this.skipped = false,
  });

  final String habitId;
  final String habitName;
  final String dayKey;

  /// Local minutes since midnight when the habit has a reminder time.
  final int? timeMinutes;
  final String? unit;
  final double? goalAmount;
  final double? increment;
  final double amount;
  final bool done;
  final bool skipped;

  bool get isTimed => timeMinutes != null;

  bool get hasGoal => goalAmount != null && goalAmount! > 0;
}
