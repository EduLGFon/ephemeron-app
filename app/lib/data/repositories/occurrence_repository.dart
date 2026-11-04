import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';
import 'package:ephemeron/features/calendar/presentation/google_calendar_colors.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Materializes recurring and single events into `occurrence_cache`
// for a rolling window (visible month +/- 1 month per PLAN 5.3).
// UI reads only from this table via [watchDay].
class OccurrenceRepository {
  OccurrenceRepository(this._db) {
    tzdata.initializeTimeZones();
  }

  final AppDatabase _db;

  static const int instanceCap = 1000;

  /// Rebuilds cache rows overlapping [windowStartUtc, windowEndUtc].
  /// Returns the number of rows inserted.
  Future<int> rebuildWindow({
    required DateTime windowStartUtc,
    required DateTime windowEndUtc,
  }) async {
    final fromMs = windowStartUtc.toUtc().millisecondsSinceEpoch;
    final toMs = windowEndUtc.toUtc().millisecondsSinceEpoch;
    final startKey = dateKey(windowStartUtc);
    final endKey = dateKey(windowEndUtc);

    // Recurring masters and their exceptions always need expansion.
    final recurringEvents =
        await (_db.select(_db.events)..where(
              (e) =>
                  e.deletedAt.isNull() &
                  (e.recurringMasterId.isNotNull() |
                      (e.rrule.isNotNull() & e.rrule.isNotValue(''))),
            ))
            .get();
    // Only load single events that can overlap the range.
    final singleEvents =
        await (_db.select(_db.events)..where(
              (e) =>
                  e.deletedAt.isNull() &
                  e.recurringMasterId.isNull() &
                  (e.rrule.isNull() | e.rrule.equals('')) &
                  (((e.startUtc.isNotNull() &
                              e.startUtc.isSmallerOrEqualValue(toMs)) &
                          ((e.endUtc.isNotNull() &
                                  e.endUtc.isBiggerOrEqualValue(fromMs)) |
                              (e.endUtc.isNull() &
                                  e.startUtc.isBiggerOrEqualValue(fromMs)))) |
                      ((e.startDate.isNotNull() &
                              e.startDate.isSmallerOrEqualValue(endKey)) &
                          ((e.endDate.isNotNull() &
                                  e.endDate.isBiggerOrEqualValue(startKey)) |
                              (e.endDate.isNull() &
                                  e.startDate.isBiggerOrEqualValue(
                                    startKey,
                                  ))))),
            ))
            .get();

    final masters = <Event>[];
    final singles = <Event>[];
    final exceptionsByMaster = <String, List<Event>>{};
    for (final e in [...recurringEvents, ...singleEvents]) {
      if (e.recurringMasterId != null) {
        exceptionsByMaster.putIfAbsent(e.recurringMasterId!, () => []).add(e);
      } else if (e.rrule != null && e.rrule!.isNotEmpty) {
        masters.add(e);
      } else {
        singles.add(e);
      }
    }

    // Only tasks due inside the range become occurrences.
    final tasks =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.completedAt.isNull() &
                  t.dueDate.isNotNull() &
                  t.dueDate.isSmallerOrEqualValue(endKey) &
                  t.dueDate.isBiggerOrEqualValue(startKey),
            ))
            .get();

    final calColors = <String, String?>{};
    for (final c in await _db.select(_db.calendars).get()) {
      calColors[c.id] = c.color;
    }
    final listColors = <String, String?>{};
    for (final l in await _db.select(_db.taskLists).get()) {
      listColors[l.id] = l.color;
    }

    final rows = <OccurrenceCacheCompanion>[];
    for (final m in masters) {
      _collectMaster(
        rows,
        m,
        exceptionsByMaster[m.id] ?? const [],
        windowStartUtc,
        windowEndUtc,
        calColors,
      );
    }
    for (final s in singles) {
      _collectSingle(rows, s, windowStartUtc, windowEndUtc, calColors);
    }
    for (final t in tasks) {
      _collectTask(rows, t, windowStartUtc, windowEndUtc, listColors);
    }

    await _db.transaction(() async {
      await (_db.delete(_db.occurrenceCache)..where(
            (c) =>
                c.startUtc.isSmallerOrEqualValue(toMs) &
                c.endUtc.isBiggerOrEqualValue(fromMs),
          ))
          .go();
      if (rows.isNotEmpty) {
        await _db.batch((batch) => batch.insertAll(_db.occurrenceCache, rows));
      }
    });
    return rows.length;
  }

  /// Deletes all cached rows for a master and its exceptions.
  Future<void> invalidateEvent(String eventId) async {
    final ids =
        await (_db.select(_db.events)..where(
              (e) => e.id.equals(eventId) | e.recurringMasterId.equals(eventId),
            ))
            .map((e) => e.id)
            .get();
    await (_db.delete(
      _db.occurrenceCache,
    )..where((c) => c.eventId.isIn(ids))).go();
  }

  Stream<List<OccurrenceCacheData>> watchWindow(
    DateTime fromUtc,
    DateTime toUtc,
  ) {
    return (_db.select(_db.occurrenceCache)
          ..where(
            (c) =>
                c.startUtc.isSmallerOrEqualValue(
                  toUtc.toUtc().millisecondsSinceEpoch,
                ) &
                c.endUtc.isBiggerOrEqualValue(
                  fromUtc.toUtc().millisecondsSinceEpoch,
                ) &
                c.eventId.isNotInQuery(_pendingDeletes(_db)),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Stream<List<OccurrenceCacheData>> watchDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where(
            (c) =>
                c.dayKey.equals(dayKey) &
                c.eventId.isNotInQuery(_pendingDeletes(_db)),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Future<List<OccurrenceCacheData>> occurrencesForDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where(
            (c) =>
                c.dayKey.equals(dayKey) &
                c.eventId.isNotInQuery(_pendingDeletes(_db)),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .get();
  }

  void _collectMaster(
    List<OccurrenceCacheCompanion> rows,
    Event master,
    List<Event> exceptions,
    DateTime rangeStart,
    DateTime rangeEnd,
    Map<String, String?> calColors,
  ) {
    if (master.isAllDay) {
      _collectAllDayMaster(rows, master, exceptions, calColors);
      return;
    }
    if (master.startUtc == null) return;
    final durationMs = (master.endUtc ?? master.startUtc!) - master.startUtc!;
    final cancelled = <int>{
      for (final ex in exceptions)
        if (ex.status == 'cancelled' && ex.originalStart != null)
          ex.originalStart!,
    };
    final overrides = <int, Event>{
      for (final ex in exceptions)
        if (ex.status != 'cancelled' && ex.originalStart != null)
          ex.originalStart!: ex,
    };
    final color = effectiveEventColor(
      eventColorId: master.colorId,
      calendarColor: calColors[master.calendarId],
      calendarId: master.calendarId,
    );
    final starts = expandOccurrences(
      startUtc: DateTime.fromMillisecondsSinceEpoch(
        master.startUtc!,
        isUtc: true,
      ),
      rrule: master.rrule!,
      tzId: master.tzId,
      rangeStartUtc: rangeStart,
      rangeEndUtc: rangeEnd,
      exdateUtcMs: cancelled,
      cap: instanceCap,
    );
    for (final s in starts) {
      final key = s.millisecondsSinceEpoch;
      final override = overrides[key];
      final startMs = override?.startUtc ?? key;
      final endMs = override?.endUtc ?? (key + durationMs);
      rows.add(
        _row(
          master.id,
          startMs,
          endMs,
          _dayKey(startMs, master.tzId),
          title: override?.title ?? master.title,
          colorId: override?.colorId ?? color,
        ),
      );
    }
  }

  void _collectAllDayMaster(
    List<OccurrenceCacheCompanion> rows,
    Event master,
    List<Event> exceptions,
    Map<String, String?> calColors,
  ) {
    if (master.startDate == null) return;
    final cancelledKeys = <String>{
      for (final ex in exceptions)
        if (ex.status == 'cancelled' && ex.originalStart != null)
          dateKey(
            DateTime.fromMillisecondsSinceEpoch(ex.originalStart!, isUtc: true),
          ),
    };
    final parts = master.startDate!.split('-');
    var cursor = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final endParts = (master.endDate ?? master.startDate)!.split('-');
    // All-day endDate is EXCLUSIVE (Google-style). spanDays is the number
    // of days the event spans; legacy rows with end==start count as one day.
    final spanDaysRaw = DateTime.utc(
      int.parse(endParts[0]),
      int.parse(endParts[1]),
      int.parse(endParts[2]),
    ).difference(cursor).inDays;
    final spanDays = spanDaysRaw < 1 ? 1 : spanDaysRaw;
    final color = effectiveEventColor(
      eventColorId: master.colorId,
      calendarColor: calColors[master.calendarId],
      calendarId: master.calendarId,
    );
    final starts = expandOccurrences(
      startUtc: cursor,
      rrule: master.rrule!,
      allDay: true,
      exdateDateKeys: cancelledKeys,
      cap: instanceCap,
    );
    for (final s in starts) {
      final day = dateKey(s);
      final dayEnd = DateTime.utc(
        s.year,
        s.month,
        s.day,
      ).add(Duration(days: spanDays));
      rows.add(
        _row(
          master.id,
          s.millisecondsSinceEpoch,
          dayEnd.millisecondsSinceEpoch - 1,
          day,
          title: master.title,
          colorId: color,
        ),
      );
    }
  }

  void _collectSingle(
    List<OccurrenceCacheCompanion> rows,
    Event e,
    DateTime rangeStart,
    DateTime rangeEnd,
    Map<String, String?> calColors,
  ) {
    final color = effectiveEventColor(
      eventColorId: e.colorId,
      calendarColor: calColors[e.calendarId],
      calendarId: e.calendarId,
    );
    if (e.isAllDay) {
      if (e.startDate == null) return;
      // All-day endDate is EXCLUSIVE (Google-style). Legacy local rows may
      // have end==start; treat those as a single day.
      final lastRaw = e.endDate ?? e.startDate!;
      var cursor = _parseDate(e.startDate!);
      var end = _parseDate(lastRaw);
      if (!end.isAfter(cursor)) {
        end = cursor.add(const Duration(days: 1));
      }
      if (e.startDate!.compareTo(dateKey(rangeEnd)) > 0) return;
      if (dateKey(end).compareTo(dateKey(rangeStart)) <= 0) return;
      var n = 0;
      while (cursor.isBefore(end)) {
        final next = cursor.add(const Duration(days: 1));
        rows.add(
          _row(
            e.id,
            cursor.millisecondsSinceEpoch,
            next.millisecondsSinceEpoch - 1,
            dateKey(cursor),
            title: e.title,
            colorId: color,
          ),
        );
        n++;
        if (n > 366) break;
        cursor = next;
      }
      return;
    }
    if (e.startUtc == null) return;
    final endMs = e.endUtc ?? e.startUtc!;
    if (endMs < rangeStart.toUtc().millisecondsSinceEpoch ||
        e.startUtc! > rangeEnd.toUtc().millisecondsSinceEpoch) {
      return;
    }
    rows.add(
      _row(
        e.id,
        e.startUtc!,
        endMs,
        _dayKey(e.startUtc!, e.tzId),
        title: e.title,
        colorId: color,
      ),
    );
  }

  void _collectTask(
    List<OccurrenceCacheCompanion> rows,
    Task t,
    DateTime rangeStart,
    DateTime rangeEnd,
    Map<String, String?> listColors,
  ) {
    if (t.dueDate == null) return;
    if (t.dueDate!.compareTo(dateKey(rangeEnd)) > 0) return;
    if (t.dueDate!.compareTo(dateKey(rangeStart)) < 0) return;
    final color = effectiveTaskColor(
      listColor: t.listId == null ? null : listColors[t.listId],
      seed: t.listId ?? t.id,
    );
    final p = t.dueDate!.split('-');
    int startMs;
    int endMs;
    if (t.dueTime == null) {
      final cursor = DateTime(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
      );
      startMs = cursor.toUtc().millisecondsSinceEpoch;
      endMs =
          cursor.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch -
          1;
    } else {
      final mins = t.dueTime!;
      final dt = DateTime(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
        mins ~/ 60,
        mins % 60,
      );
      startMs = dt.toUtc().millisecondsSinceEpoch;
      final dur = Duration(minutes: t.durationMin ?? 30);
      endMs = dt.add(dur).toUtc().millisecondsSinceEpoch;
    }
    rows.add(
      _row(t.id, startMs, endMs, t.dueDate!, title: t.title, colorId: color),
    );
  }

  OccurrenceCacheCompanion _row(
    String eventId,
    int startMs,
    int endMs,
    String dayKeyValue, {
    String? title,
    String? colorId,
  }) {
    return OccurrenceCacheCompanion.insert(
      id: newId(),
      eventId: eventId,
      title: Value(title),
      colorId: Value(colorId),
      startUtc: startMs,
      endUtc: endMs,
      dayKey: dayKeyValue,
    );
  }

  String _dayKey(int utcMs, String? tzId) {
    if (tzId == null) {
      // Floating local event: group by device-local date so the timeline
      // (which renders local wall time) shows it on the expected day.
      return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs));
    }
    if (tzId == 'UTC') {
      return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true));
    }
    try {
      final loc = tz.getLocation(tzId);
      return dateKey(
        tz.TZDateTime.from(
          DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true),
          loc,
        ),
      );
    } catch (_) {
      // Non-IANA abbreviations (e.g. "-03") must not crash the rebuild.
      return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs));
    }
  }

  DateTime _parseDate(String ymd) {
    final p = ymd.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

/// Event or task ids queued for deletion.
JoinedSelectStatement _pendingDeletes(AppDatabase db) {
  return db.selectOnly(db.pendingOperations)
    ..addColumns([db.pendingOperations.entityId])
    ..where(
      db.pendingOperations.entity.isIn(const ['event', 'task']) &
          db.pendingOperations.op.equals('delete'),
    );
}
