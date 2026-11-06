part of '../occurrence_repository.dart';

Expression<bool> _taskOccurrenceStateSuppressed($OccurrenceCacheTable c) {
  // Suppress task projections that have local per-occurrence completion state.
  // Joins through tasks to resolve series_id (recurrenceKey may differ only in
  // representation; occurrenceDate matches cache day_key).
  return const CustomExpression<bool>(
    "(occurrence_cache.source_type = 'event' OR NOT EXISTS ("
    'SELECT 1 FROM task_occurrence_states tos '
    'JOIN tasks t ON COALESCE(t.series_id, t.id) = tos.series_id '
    'WHERE t.id = occurrence_cache.event_id '
    'AND tos.occurrence_date = occurrence_cache.day_key))',
  );
}

extension OccurrenceRepositoryQueries on OccurrenceRepository {
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
                c.eventId.isNotInQuery(_pendingDeletes(_db)) &
                _taskOccurrenceStateSuppressed(c),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Stream<List<OccurrenceCacheData>> watchDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where(
            (c) =>
                c.dayKey.equals(dayKey) &
                c.eventId.isNotInQuery(_pendingDeletes(_db)) &
                _taskOccurrenceStateSuppressed(c),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .watch();
  }

  Future<List<OccurrenceCacheData>> occurrencesForDay(String dayKey) {
    return (_db.select(_db.occurrenceCache)
          ..where(
            (c) =>
                c.dayKey.equals(dayKey) &
                c.eventId.isNotInQuery(_pendingDeletes(_db)) &
                _taskOccurrenceStateSuppressed(c),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.startUtc)]))
        .get();
  }
}
