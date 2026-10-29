// Countdown next-date math. Pure Dart.
DateTime countdownNextDate({
  required int month,
  required int day,
  required DateTime today,
  bool yearlyRepeat = true,
}) {
  DateTime candidate(int y) {
    if (month == 2 && day == 29 && !_isLeap(y)) return DateTime(y, 2, 28);
    final last = DateTime(y, month + 1, 0).day;
    return DateTime(y, month, day > last ? last : day);
  }

  var next = candidate(today.year);
  if (yearlyRepeat &&
      DateTime(
        next.year,
        next.month,
        next.day,
      ).isBefore(DateTime(today.year, today.month, today.day))) {
    next = candidate(today.year + 1);
  }
  return next;
}

bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);

/// Whole days from today (0 = today). Negative when passed and not repeating.
int daysUntil(DateTime target, DateTime today) {
  final a = DateTime(today.year, today.month, today.day);
  final b = DateTime(target.year, target.month, target.day);
  return b.difference(a).inDays;
}
