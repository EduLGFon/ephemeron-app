part of '../event_repository.dart';

mixin _EventHelperOps on _EventRepositoryBase {
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
}
