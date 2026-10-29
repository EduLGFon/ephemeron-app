import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _weekdays = {
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

class RecurrenceRule {
  RecurrenceRule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.untilUtc,
    this.untilDate,
    this.byDay = const [],
    this.byMonthDay = const [],
    this.byMonth = const [],
    this.bySetPos = const [],
    this.wkst = 'MO',
    this.allDay = false,
  });

  final String freq;
  final int interval;
  final int? count;
  final DateTime? untilUtc;
  final String? untilDate;
  final List<String> byDay;
  final List<int> byMonthDay;
  final List<int> byMonth;
  final List<int> bySetPos;
  final String wkst;
  final bool allDay;

  static RecurrenceRule parse(String rrule, {bool allDay = false}) {
    _ensureTz();
    var s = rrule.trim();
    if (s.toUpperCase().startsWith('RRULE:')) s = s.substring(6);
    final parts = s.split(';');
    String freq = 'DAILY';
    int interval = 1;
    int? count;
    DateTime? untilUtc;
    String? untilDate;
    List<String> byDay = [];
    List<int> byMonthDay = [];
    List<int> byMonth = [];
    List<int> bySetPos = [];
    String wkst = 'MO';
    for (final p in parts) {
      if (p.isEmpty) continue;
      final kv = p.split('=');
      if (kv.length != 2) continue;
      final k = kv[0].toUpperCase();
      final v = kv[1];
      switch (k) {
        case 'FREQ':
          freq = v.toUpperCase();
          break;
        case 'INTERVAL':
          interval = int.tryParse(v) ?? 1;
          if (interval < 1) interval = 1;
          break;
        case 'COUNT':
          count = int.tryParse(v);
          break;
        case 'UNTIL':
          if (v.endsWith('Z') || v.contains('T')) {
            untilUtc = _parseUtc(v);
          } else {
            if (v.length == 8) {
              untilDate =
                  '${v.substring(0, 4)}-${v.substring(4, 6)}-${v.substring(6, 8)}';
            } else {
              untilDate = v;
            }
          }
          break;
        case 'BYDAY':
          byDay = v.split(',').map((e) => e.trim()).toList();
          break;
        case 'BYMONTHDAY':
          byMonthDay = v.split(',').map(int.parse).toList();
          break;
        case 'BYMONTH':
          byMonth = v.split(',').map(int.parse).toList();
          break;
        case 'BYSETPOS':
          bySetPos = v.split(',').map(int.parse).toList();
          break;
        case 'WKST':
          wkst = v.toUpperCase();
          break;
      }
    }
    return RecurrenceRule(
      freq: freq,
      interval: interval,
      count: count,
      untilUtc: untilUtc,
      untilDate: untilDate,
      byDay: byDay,
      byMonthDay: byMonthDay,
      byMonth: byMonth,
      bySetPos: bySetPos,
      wkst: wkst,
      allDay: allDay,
    );
  }

  static DateTime _parseUtc(String v) {
    final s = v.replaceAll('Z', '');
    if (s.length == 8) {
      return DateTime.utc(
        int.parse(s.substring(0, 4)),
        int.parse(s.substring(4, 6)),
        int.parse(s.substring(6, 8)),
      );
    }
    return DateTime.utc(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(9, 11)),
      int.parse(s.substring(11, 13)),
      s.length >= 15 ? int.parse(s.substring(13, 15)) : 0,
    );
  }
}

bool _tzReady = false;
void _ensureTz() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

List<DateTime> expandOccurrences({
  required DateTime startUtc,
  required String rrule,
  String? tzId,
  bool allDay = false,
  DateTime? rangeStartUtc,
  DateTime? rangeEndUtc,
  Set<int> exdateUtcMs = const {},
  Set<String> exdateDateKeys = const {},
  List<DateTime> rdatesUtc = const [],
  int cap = 1000,
}) {
  _ensureTz();
  final loc = (tzId == null || tzId == 'UTC') ? tz.UTC : tz.getLocation(tzId);
  final start = tz.TZDateTime.from(startUtc.toUtc(), loc);
  final rule = RecurrenceRule.parse(rrule, allDay: allDay);
  final wkstDart = _weekdayFromWkst(rule.wkst);

  bool excluded(tz.TZDateTime occ) {
    if (allDay) {
      final key =
          '${occ.year.toString().padLeft(4, '0')}-${occ.month.toString().padLeft(2, '0')}-${occ.day.toString().padLeft(2, '0')}';
      return exdateDateKeys.contains(key);
    }
    return exdateUtcMs.contains(occ.toUtc().millisecondsSinceEpoch);
  }

  final results = <tz.TZDateTime>[];

  DateTime? untilInstant;
  String? untilKey;
  if (rule.untilUtc != null) {
    untilInstant = rule.untilUtc!.toUtc();
  } else if (rule.untilDate != null) {
    untilKey = rule.untilDate!;
  }

  bool pastUntil(tz.TZDateTime cursor) {
    if (untilInstant != null) {
      final occ = allDay
          ? tz.TZDateTime(loc, cursor.year, cursor.month, cursor.day)
          : tz.TZDateTime(
              loc,
              cursor.year,
              cursor.month,
              cursor.day,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
            );
      return occ.toUtc().isAfter(untilInstant);
    }
    if (untilKey != null) {
      final key =
          '${cursor.year.toString().padLeft(4, '0')}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
      return key.compareTo(untilKey) > 0;
    }
    return false;
  }

  final startDateOnly = tz.TZDateTime(loc, start.year, start.month, start.day);
  var cursor = startDateOnly;
  int safety = 0;
  final maxSafety = 366 * 200;
  int matched = 0;
  while (results.length < cap && safety < maxSafety) {
    safety++;
    if (rule.count != null && matched >= rule.count!) break;
    if (pastUntil(cursor)) break;
    if (rangeEndUtc != null) {
      final cursorInstant = allDay
          ? tz.TZDateTime(loc, cursor.year, cursor.month, cursor.day).toUtc()
          : tz.TZDateTime(
              loc,
              cursor.year,
              cursor.month,
              cursor.day,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
            ).toUtc();
      if (cursorInstant.isAfter(rangeEndUtc.toUtc())) break;
    }

    if (_matchesDay(cursor, start, rule, wkstDart)) {
      matched++;
      final occ = allDay
          ? tz.TZDateTime(loc, cursor.year, cursor.month, cursor.day)
          : tz.TZDateTime(
              loc,
              cursor.year,
              cursor.month,
              cursor.day,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
            );
      bool inRange = true;
      if (rangeStartUtc != null) {
        if (occ.toUtc().isBefore(rangeStartUtc.toUtc())) inRange = false;
      }
      if (inRange && !excluded(occ)) {
        results.add(occ);
      }
    }

    cursor = cursor.add(const Duration(days: 1));
  }

  for (final rd in rdatesUtc) {
    final occ = tz.TZDateTime.from(rd.toUtc(), loc);
    if (untilInstant != null && occ.toUtc().isAfter(untilInstant)) continue;
    if (untilKey != null) {
      final key =
          '${occ.year.toString().padLeft(4, '0')}-${occ.month.toString().padLeft(2, '0')}-${occ.day.toString().padLeft(2, '0')}';
      if (key.compareTo(untilKey) > 0) continue;
    }
    if (rangeStartUtc != null && occ.toUtc().isBefore(rangeStartUtc.toUtc())) {
      continue;
    }
    if (rangeEndUtc != null && occ.toUtc().isAfter(rangeEndUtc.toUtc())) {
      continue;
    }
    if (excluded(occ)) continue;
    if (!results.any(
      (r) =>
          r.toUtc().millisecondsSinceEpoch ==
          occ.toUtc().millisecondsSinceEpoch,
    )) {
      results.add(occ);
    }
  }

  results.sort((a, b) => a.compareTo(b));
  if (results.length > cap) {
    results.removeRange(cap, results.length);
  }

  return results.map((e) => e.toUtc()).toList();
}

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
