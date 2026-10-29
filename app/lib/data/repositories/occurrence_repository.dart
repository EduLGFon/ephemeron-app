import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';
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
    final events = await (_db.select(
      _db.events,
    )..where((e) => e.deletedAt.isNull())).get();

    final masters = <Event>[];
    final singles = <Event>[];
    final exceptionsByMaster = <String, List<Event>>{};
    for (final e in events) {
      if (e.recurringMasterId != null) {
        exceptionsByMaster.putIfAbsent(e.recurringMasterId!, () => []).add(e);
      } else if (e.rrule != null && e.rrule!.isNotEmpty) {
        masters.add(e);
      } else {
        singles.add(e);
      }
    }

    var inserted = 0;
    await _db.transaction(() async {
      await (_db.delete(_db.occurrenceCache)..where(
            (c) =>
                c.startUtc.isSmallerOrEqualValue(toMs) &
                c.endUtc.isBiggerOrEqualValue(fromMs),
          ))
          .go();
      for (final m in masters) {
        inserted += await _expandMaster(
          m,
          exceptionsByMaster[m.id] ?? const [],
          windowStartUtc,
          windowEndUtc,
        );
      }
      for (final s in singles) {
        inserted += await _insertSingle(s, windowStartUtc, windowEndUtc);
      }
    });
    return inserted;
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
                ),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Stream<List<OccurrenceCacheData>> watchDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where((c) => c.dayKey.equals(dayKey))
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Future<List<OccurrenceCacheData>> occurrencesForDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where((c) => c.dayKey.equals(dayKey))
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .get();
  }

  Future<int> _expandMaster(
    Event master,
    List<Event> exceptions,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    if (master.isAllDay) return _expandAllDayMaster(master, exceptions);
    if (master.startUtc == null) return 0;
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
    var n = 0;
    for (final s in starts) {
      final key = s.millisecondsSinceEpoch;
      final override = overrides[key];
      final startMs = override?.startUtc ?? key;
      final endMs = override?.endUtc ?? (key + durationMs);
      await _insertRow(
        master.id,
        startMs,
        endMs,
        _dayKey(startMs, master.tzId),
      );
      n++;
    }
    return n;
  }

  Future<int> _expandAllDayMaster(Event master, List<Event> exceptions) async {
    if (master.startDate == null) return 0;
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
    final spanDays = DateTime.utc(
      int.parse(endParts[0]),
      int.parse(endParts[1]),
      int.parse(endParts[2]),
    ).difference(cursor).inDays;
    final starts = expandOccurrences(
      startUtc: cursor,
      rrule: master.rrule!,
      allDay: true,
      exdateDateKeys: cancelledKeys,
      cap: instanceCap,
    );
    var n = 0;
    for (final s in starts) {
      final day = dateKey(s);
      final dayEnd = DateTime.utc(
        s.year,
        s.month,
        s.day,
      ).add(Duration(days: spanDays + 1));
      await _insertRow(
        master.id,
        s.millisecondsSinceEpoch,
        dayEnd.millisecondsSinceEpoch - 1,
        day,
      );
      n++;
    }
    return n;
  }

  Future<int> _insertSingle(
    Event e,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    if (e.isAllDay) {
      if (e.startDate == null) return 0;
      if (e.startDate!.compareTo(dateKey(rangeEnd)) > 0) return 0;
      final last = e.endDate ?? e.startDate!;
      if (last.compareTo(dateKey(rangeStart)) < 0) return 0;
      var cursor = _parseDate(e.startDate!);
      final end = _parseDate(last);
      var n = 0;
      while (!cursor.isAfter(end)) {
        final next = cursor.add(const Duration(days: 1));
        await _insertRow(
          e.id,
          cursor.millisecondsSinceEpoch,
          next.millisecondsSinceEpoch - 1,
          dateKey(cursor),
        );
        n++;
        if (n > 366) break;
        cursor = next;
      }
      return n;
    }
    if (e.startUtc == null) return 0;
    final endMs = e.endUtc ?? e.startUtc!;
    if (endMs < rangeStart.toUtc().millisecondsSinceEpoch ||
        e.startUtc! > rangeEnd.toUtc().millisecondsSinceEpoch) {
      return 0;
    }
    await _insertRow(e.id, e.startUtc!, endMs, _dayKey(e.startUtc!, e.tzId));
    return 1;
  }

  Future<void> _insertRow(
    String eventId,
    int startMs,
    int endMs,
    String dayKeyValue,
  ) {
    return _db
        .into(_db.occurrenceCache)
        .insert(
          OccurrenceCacheCompanion.insert(
            id: newId(),
            eventId: eventId,
            startUtc: startMs,
            endUtc: endMs,
            dayKey: dayKeyValue,
          ),
        );
  }

  String _dayKey(int utcMs, String? tzId) {
    if (tzId == null || tzId == 'UTC') {
      return dateKey(DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true));
    }
    final loc = tz.getLocation(tzId);
    return dateKey(
      tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true),
        loc,
      ),
    );
  }

  DateTime _parseDate(String ymd) {
    final p = ymd.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}
