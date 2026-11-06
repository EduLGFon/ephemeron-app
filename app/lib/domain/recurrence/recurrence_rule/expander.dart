part of '../recurrence_rule.dart';

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
  final loc = _safeLocation(tzId);
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
