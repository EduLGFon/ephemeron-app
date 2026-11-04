// Lightweight view of a scheduled habit for a single calendar day.
class HabitCalendarEntry {
  const HabitCalendarEntry({
    required this.habitId,
    required this.habitName,
    required this.dayKey,
    this.done = false,
    this.skipped = false,
  });

  final String habitId;
  final String habitName;
  final String dayKey;
  final bool done;
  final bool skipped;
}
