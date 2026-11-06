part of '../occurrence_repository.dart';

extension OccurrenceRepositoryWindowRebuild on OccurrenceRepository {
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

    // Tasks: load all open tasks so overdue recurring series still project.
    final tasks =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.completedAt.isNull() &
                  t.id.isNotInQuery(_pendingDeletes(_db)),
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
    final siblings = <String>{};
    final allTasks = await _db.select(_db.tasks).get();
    for (final t in allTasks) {
      if (t.seriesId != null &&
          t.recurrenceKey != null &&
          t.completedAt != null) {
        siblings.add('${t.seriesId}|${t.recurrenceKey}');
      }
    }
    for (final t in tasks) {
      _collectTask(rows, t, windowStartUtc, windowEndUtc, listColors, siblings);
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
}
