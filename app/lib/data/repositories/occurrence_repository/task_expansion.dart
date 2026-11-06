part of '../occurrence_repository.dart';

extension OccurrenceRepositoryTaskExpansion on OccurrenceRepository {
  void _collectTask(
    List<OccurrenceCacheCompanion> rows,
    Task t,
    DateTime rangeStart,
    DateTime rangeEnd,
    Map<String, String?> listColors,
    Set<String> siblings,
  ) {
    final color = effectiveTaskColor(
      listColor: t.listId == null ? null : listColors[t.listId],
      seed: t.listId ?? t.id,
    );
    final rangeStartKey = dateKey(rangeStart);
    final rangeEndKey = dateKey(rangeEnd);

    final isRecurring = t.rrule != null && t.rrule!.isNotEmpty;
    if (!isRecurring) {
      // Non-recurring.
      if (t.plannedStart != null && t.plannedStart!.isNotEmpty) {
        // Timed block converted from local to UTC.
        final startLocal = DateTime.parse(t.plannedStart!);
        final endLocal = t.plannedEnd != null && t.plannedEnd!.isNotEmpty
            ? DateTime.parse(t.plannedEnd!)
            : startLocal.add(Duration(minutes: t.durationMin ?? 30));
        final startMs = startLocal.toUtc().millisecondsSinceEpoch;
        final endMs = endLocal.toUtc().millisecondsSinceEpoch;
        final day = dateKey(startLocal);
        if (day.compareTo(rangeEndKey) > 0) return;
        if (day.compareTo(rangeStartKey) < 0) return;
        rows.add(
          _row(
            t.id,
            startMs,
            endMs,
            day,
            title: t.title,
            colorId: color,
            sourceType: 'task',
          ),
        );
        return;
      }
      final planned = t.plannedDate;
      final day = planned ?? t.dueDate;
      if (day == null) return;
      if (day.compareTo(rangeEndKey) > 0) return;
      if (day.compareTo(rangeStartKey) < 0) return;
      int startMs;
      int endMs;
      if (planned != null || t.dueTime == null) {
        final cursor = DateTime(
          int.parse(day.split('-')[0]),
          int.parse(day.split('-')[1]),
          int.parse(day.split('-')[2]),
        );
        startMs = cursor.toUtc().millisecondsSinceEpoch;
        endMs =
            cursor.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch -
            1;
      } else {
        final mins = t.dueTime!;
        final dt = DateTime(
          int.parse(day.split('-')[0]),
          int.parse(day.split('-')[1]),
          int.parse(day.split('-')[2]),
          mins ~/ 60,
          mins % 60,
        );
        startMs = dt.toUtc().millisecondsSinceEpoch;
        final dur = Duration(minutes: t.durationMin ?? 30);
        endMs = dt.add(dur).toUtc().millisecondsSinceEpoch;
      }
      rows.add(
        _row(
          t.id,
          startMs,
          endMs,
          day,
          title: t.title,
          colorId: color,
          sourceType: 'task',
        ),
      );
      return;
    }

    // Recurring open task projection.
    final currentEffective = t.plannedDate ?? t.dueDate;
    if (currentEffective == null && t.plannedStart == null) return;

    DateTime baseUtc;
    bool allDay;
    if (t.plannedStart != null && t.plannedStart!.isNotEmpty) {
      baseUtc = DateTime.parse(t.plannedStart!).toUtc();
      allDay = false;
    } else if (t.plannedDate != null) {
      final bp = t.plannedDate!.split('-');
      baseUtc = DateTime.utc(
        int.parse(bp[0]),
        int.parse(bp[1]),
        int.parse(bp[2]),
      );
      allDay = true;
    } else if (t.dueDate != null && t.dueTime != null) {
      final bp = t.dueDate!.split('-');
      baseUtc = DateTime.utc(
        int.parse(bp[0]),
        int.parse(bp[1]),
        int.parse(bp[2]),
        t.dueTime! ~/ 60,
        t.dueTime! % 60,
      );
      allDay = false;
    } else if (t.dueDate != null) {
      final bp = t.dueDate!.split('-');
      baseUtc = DateTime.utc(
        int.parse(bp[0]),
        int.parse(bp[1]),
        int.parse(bp[2]),
      );
      allDay = true;
    } else {
      return;
    }

    final occs = expandOccurrences(
      startUtc: baseUtc,
      rrule: t.rrule!,
      tzId: null,
      allDay: allDay,
      rangeStartUtc: rangeStart,
      rangeEndUtc: rangeEnd,
      cap: OccurrenceRepository.instanceCap,
    );
    final seriesId = t.seriesId ?? t.id;

    // Current occurrence date key base for dayDelta.
    final baseDateKey =
        t.recurrenceKey ??
        t.plannedDate ??
        t.dueDate ??
        (t.plannedStart != null && t.plannedStart!.length >= 10
            ? t.plannedStart!.substring(0, 10)
            : null);
    for (final s in occs) {
      final isAllDayResult = allDay;
      final String occKey;
      DateTime localOcc;
      if (isAllDayResult) {
        occKey = dateKey(s);
        localOcc = DateTime(s.year, s.month, s.day);
      } else {
        localOcc = s.toLocal();
        occKey =
            '${localOcc.year.toString().padLeft(4, '0')}-'
            '${localOcc.month.toString().padLeft(2, '0')}-'
            '${localOcc.day.toString().padLeft(2, '0')}';
      }
      if (siblings.contains('$seriesId|$occKey')) continue;

      final baseKey = baseDateKey ?? occKey;
      final dayDelta = _parseDate(
        occKey,
      ).difference(_parseDate(baseKey)).inDays;

      int startMs;
      int endMs;
      String dayKeyOut = occKey;
      if (t.plannedStart != null && t.plannedStart!.isNotEmpty) {
        final startLocal = DateTime.parse(t.plannedStart!);
        final shiftedStart = DateTime(
          startLocal.year,
          startLocal.month,
          startLocal.day + dayDelta,
          startLocal.hour,
          startLocal.minute,
        );
        DateTime shiftedEnd;
        if (t.plannedEnd != null && t.plannedEnd!.isNotEmpty) {
          final endLocal = DateTime.parse(t.plannedEnd!);
          shiftedEnd = DateTime(
            endLocal.year,
            endLocal.month,
            endLocal.day + dayDelta,
            endLocal.hour,
            endLocal.minute,
          );
        } else {
          shiftedEnd = shiftedStart.add(Duration(minutes: t.durationMin ?? 30));
        }
        if (!shiftedEnd.isAfter(shiftedStart)) {
          shiftedEnd = shiftedStart.add(Duration(minutes: t.durationMin ?? 30));
        }
        startMs = shiftedStart.toUtc().millisecondsSinceEpoch;
        endMs = shiftedEnd.toUtc().millisecondsSinceEpoch;
        dayKeyOut = dateKey(shiftedStart);
      } else if (t.plannedDate != null || t.dueTime == null) {
        final cursor = DateTime(localOcc.year, localOcc.month, localOcc.day);
        startMs = cursor.toUtc().millisecondsSinceEpoch;
        endMs =
            cursor.add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch -
            1;
      } else {
        final mins = t.dueTime!;
        final dt = DateTime(
          localOcc.year,
          localOcc.month,
          localOcc.day,
          mins ~/ 60,
          mins % 60,
        );
        startMs = dt.toUtc().millisecondsSinceEpoch;
        final dur = Duration(minutes: t.durationMin ?? 30);
        endMs = dt.add(dur).toUtc().millisecondsSinceEpoch;
      }
      rows.add(
        _row(
          t.id,
          startMs,
          endMs,
          dayKeyOut,
          title: t.title,
          colorId: color,
          sourceType: 'task',
        ),
      );
    }
  }
}
