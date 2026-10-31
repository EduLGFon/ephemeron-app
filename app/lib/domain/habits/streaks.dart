// Habit streak engine. Pure Dart.
// Skip/vacation days never break a streak; weekly-target streaks count weeks.
import 'date_key.dart';

class HabitSpec {
  HabitSpec({
    required this.frequency,
    this.weekdaysMask = 0,
    this.weeklyTarget = 0,
    this.intervalDays = 0,
    this.startDate,
  });
  final String frequency;
  final int weekdaysMask;
  final int weeklyTarget;
  final int intervalDays;
  final String? startDate;
}

bool _isScheduled(HabitSpec spec, DateTime day) {
  switch (spec.frequency) {
    case 'weekdays':
      return (spec.weekdaysMask & (1 << ((day.weekday - 1) % 7))) != 0;
    case 'interval':
      if (spec.startDate == null || spec.intervalDays < 1) return true;
      return day.difference(parseKey(spec.startDate!)).inDays %
              spec.intervalDays ==
          0;
    default:
      return true;
  }
}

int currentStreak(
  HabitSpec spec,
  String todayKey,
  bool Function(String dayKey) isDone,
  bool Function(String dayKey) isSkipped,
) {
  if (spec.frequency == 'weekly') {
    return _weeklyStreak(spec, todayKey, isDone, isSkipped);
  }
  var streak = 0;
  var cur = parseKey(todayKey);
  final start = spec.startDate == null ? null : parseKey(spec.startDate!);
  while (true) {
    if (start != null && cur.isBefore(start)) break;
    if (!_isScheduled(spec, cur)) {
      cur = cur.subtract(const Duration(days: 1));
      continue;
    }
    final key = habitDateKey(cur);
    if (isDone(key)) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
      continue;
    }
    if (isSkipped(key)) {
      cur = cur.subtract(const Duration(days: 1));
      continue;
    }
    break;
  }
  return streak;
}

int bestStreak(
  HabitSpec spec,
  String todayKey,
  bool Function(String dayKey) isDone,
  bool Function(String dayKey) isSkipped,
) {
  if (spec.frequency == 'weekly') {
    return _bestWeekly(spec, todayKey, isDone, isSkipped);
  }
  var best = 0, run = 0;
  var cur = spec.startDate == null
      ? parseKey(todayKey).subtract(const Duration(days: 400))
      : parseKey(spec.startDate!);
  final end = parseKey(todayKey);
  while (!cur.isAfter(end)) {
    if (!_isScheduled(spec, cur)) {
      cur = cur.add(const Duration(days: 1));
      continue;
    }
    final key = habitDateKey(cur);
    if (isDone(key)) {
      run++;
      if (run > best) best = run;
    } else if (isSkipped(key)) {
      // Skipped days bridge the run without extending it.
    } else {
      run = 0;
    }
    cur = cur.add(const Duration(days: 1));
  }
  return best;
}

DateTime _mondayOf(DateTime d) =>
    d.subtract(Duration(days: (d.weekday - 1) % 7));

int _weeklyStreak(
  HabitSpec spec,
  String todayKey,
  bool Function(String) isDone,
  bool Function(String) isSkipped,
) {
  final target = spec.weeklyTarget < 1 ? 1 : spec.weeklyTarget;
  int weekDone(DateTime monday) {
    var done = 0;
    for (var i = 0; i < 7; i++) {
      if (isDone(habitDateKey(monday.add(Duration(days: i))))) done++;
    }
    return done;
  }

  var streak = 0;
  var monday = _mondayOf(parseKey(todayKey));
  // An in-progress week below target does not break the streak.
  if (weekDone(monday) < target) {
    monday = monday.subtract(const Duration(days: 7));
  }
  while (true) {
    if (weekDone(monday) >= target) {
      streak++;
      monday = monday.subtract(const Duration(days: 7));
      continue;
    }
    break;
  }
  return streak;
}

int _bestWeekly(
  HabitSpec spec,
  String todayKey,
  bool Function(String) isDone,
  bool Function(String) isSkipped,
) {
  final target = spec.weeklyTarget < 1 ? 1 : spec.weeklyTarget;
  final end = parseKey(todayKey);
  var monday = _mondayOf(end).subtract(const Duration(days: 7 * 104));
  final counts = <String, int>{};
  var cur = monday;
  while (!cur.isAfter(end)) {
    final wk = habitDateKey(_mondayOf(cur));
    if (isDone(habitDateKey(cur))) counts[wk] = (counts[wk] ?? 0) + 1;
    cur = cur.add(const Duration(days: 1));
  }
  var best = 0, run = 0;
  cur = monday;
  while (!cur.isAfter(end)) {
    if ((counts[habitDateKey(cur)] ?? 0) >= target) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
    cur = cur.add(const Duration(days: 7));
  }
  return best;
}
