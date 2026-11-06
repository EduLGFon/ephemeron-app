part of '../recurrence_rule.dart';

bool _matchesDay(
  tz.TZDateTime d,
  tz.TZDateTime start,
  RecurrenceRule rule,
  int wkstDart,
) {
  switch (rule.freq) {
    case 'DAILY':
      final dayDiff = d
          .difference(
            tz.TZDateTime(start.location, start.year, start.month, start.day),
          )
          .inDays;
      return dayDiff >= 0 && dayDiff % rule.interval == 0;
    case 'WEEKLY':
      final wds = rule.byDay.isEmpty
          ? {start.weekday}
          : rule.byDay.map(_weekdayFromEntry).toSet();
      if (!wds.contains(d.weekday)) return false;
      final startWeek = _weekStart(start, wkstDart);
      final dWeek = _weekStart(d, wkstDart);
      final weekDiff = dWeek.difference(startWeek).inDays ~/ 7;
      return weekDiff >= 0 && weekDiff % rule.interval == 0;
    case 'MONTHLY':
      final startMonthIndex = start.year * 12 + start.month;
      final dMonthIndex = d.year * 12 + d.month;
      final monthDiff = dMonthIndex - startMonthIndex;
      if (monthDiff < 0 || monthDiff % rule.interval != 0) return false;
      return _monthDayMatches(d, rule, start.day);
    case 'YEARLY':
      final yearDiff = d.year - start.year;
      if (yearDiff < 0 || yearDiff % rule.interval != 0) return false;
      if (rule.byMonth.isNotEmpty && !rule.byMonth.contains(d.month)) {
        return false;
      }
      if (rule.byMonth.isEmpty && d.month != start.month) return false;
      final effectiveStartDay =
          (start.month == 2 && start.day == 29 && !_isLeap(d.year))
          ? 28
          : start.day;
      return _monthDayMatches(d, rule, effectiveStartDay);
    default:
      return false;
  }
}

int _weekdayFromEntry(String e) {
  final letters = e.replaceAll(RegExp(r'[^A-Z]'), '');
  return _weekdays[letters] ?? DateTime.monday;
}

int _ordinalFromEntry(String e) {
  final m = RegExp(r'^(-?\d+)').firstMatch(e);
  if (m == null) return 0;
  return int.parse(m.group(1)!);
}

tz.TZDateTime _weekStart(tz.TZDateTime d, int wkstDart) {
  int diff = (d.weekday - wkstDart + 7) % 7;
  final day = d.subtract(Duration(days: diff));
  return tz.TZDateTime(d.location, day.year, day.month, day.day);
}

int _weekdayFromWkst(String wkst) {
  return _weekdays[wkst] ?? DateTime.monday;
}

bool _monthDayMatches(tz.TZDateTime d, RecurrenceRule rule, int startDay) {
  if (rule.byMonthDay.isNotEmpty) {
    final lastDay = DateTime(d.year, d.month + 1, 0).day;
    for (final md in rule.byMonthDay) {
      final target = md < 0 ? lastDay + md + 1 : md;
      if (d.day == target) return true;
    }
    return false;
  }
  final ordinalEntries = rule.byDay
      .where((e) => RegExp(r'^-?\d+').hasMatch(e))
      .toList();
  if (ordinalEntries.isNotEmpty) {
    for (final e in ordinalEntries) {
      final ord = _ordinalFromEntry(e);
      final wd = _weekdayFromEntry(e);
      if (d.weekday != wd) continue;
      if (_isNthWeekdayOfMonth(d, ord)) return true;
    }
    return false;
  }
  final simpleDays = rule.byDay
      .where((e) => !RegExp(r'^-?\d+').hasMatch(e))
      .toList();
  if (simpleDays.isNotEmpty) {
    if (!simpleDays.map(_weekdayFromEntry).contains(d.weekday)) return false;
    return true;
  }
  if (startDay > DateTime(d.year, d.month + 1, 0).day) return false;
  return d.day == startDay;
}

bool _isNthWeekdayOfMonth(tz.TZDateTime d, int ord) {
  if (ord > 0) {
    final first = _firstWeekdayOfMonth(d.year, d.month, d.weekday);
    final targetDay = first + (ord - 1) * 7;
    if (targetDay > DateTime(d.year, d.month + 1, 0).day) return false;
    return d.day == targetDay;
  } else if (ord < 0) {
    final last = _lastWeekdayOfMonth(d.year, d.month, d.weekday);
    final targetDay = last + (ord + 1) * 7;
    if (targetDay < 1) return false;
    return d.day == targetDay;
  }
  return false;
}

bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);

int _firstWeekdayOfMonth(int year, int month, int weekday) {
  int day = 1;
  while (DateTime(year, month, day).weekday != weekday) {
    day++;
  }
  return day;
}

int _lastWeekdayOfMonth(int year, int month, int weekday) {
  int day = DateTime(year, month + 1, 0).day;
  while (DateTime(year, month, day).weekday != weekday) {
    day--;
  }
  return day;
}
