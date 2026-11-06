part of '../event_repository.dart';

extension EventRepositoryQueries on EventRepository {
  Future<List<Event>> exceptionsOf(String masterId) {
    return (dbSelect()..where(
          (e) => e.recurringMasterId.equals(masterId) & e.deletedAt.isNull(),
        ))
        .get();
  }

  /// Global-search hits over live events, newest first.
  Future<List<Event>> searchEvents(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = sanitizeSearch(q);
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    return (dbSelect()
          ..where(
            (e) =>
                e.deletedAt.isNull() &
                (e.title.like(like) |
                    e.location.like(like) |
                    e.notes.like(like)),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)])
          ..limit(limit))
        .get();
  }

  /// Returns events in [calendarId] overlapping [startUtc, endUtc).
  Future<List<Event>> overlappingEvents({
    required String calendarId,
    required DateTime startUtc,
    required DateTime endUtc,
    String? excludeId,
  }) async {
    final rows =
        await (dbSelect()..where(
              (e) => e.calendarId.equals(calendarId) & e.deletedAt.isNull(),
            ))
            .get();
    final s = startUtc.toUtc().millisecondsSinceEpoch;
    final e = endUtc.toUtc().millisecondsSinceEpoch;
    return rows.where((ev) {
      if (excludeId != null && ev.id == excludeId) return false;
      final es = ev.startUtc;
      final ee = ev.endUtc ?? ev.startUtc;
      if (es == null || ee == null) return false;
      return es < e && s < ee;
    }).toList();
  }

  Stream<List<Event>> watchExceptions(String masterId) {
    return (dbSelect()..where((e) => e.recurringMasterId.equals(masterId)))
        .watch();
  }
}
