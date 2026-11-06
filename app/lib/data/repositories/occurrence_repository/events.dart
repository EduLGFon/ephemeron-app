part of '../occurrence_repository.dart';

// Materializes event rows (recurring masters, all-day masters, singles)
// into `occurrence_cache` companions.
mixin _EventCacheOps on _OccurrenceRepositoryBase {
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
      cap: OccurrenceRepository.instanceCap,
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
      cap: OccurrenceRepository.instanceCap,
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
}
