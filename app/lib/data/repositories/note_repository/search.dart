part of '../note_repository.dart';

mixin _NoteSearchOps on _NoteRepositoryBase {
  Future<List<NoteSearchHit>> searchNotes(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = sanitizeSearch(q);
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    final rows =
        await (_db.select(_db.notes)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.id.isNotInQuery(
                      pendingIdsQuery(
                        _db,
                        entity: 'note',
                        ops: const {'trash'},
                      ),
                    ) &
                    (t.title.like(like) | t.body.like(like)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return [
      for (final n in rows) NoteSearchHit(note: n, snippet: _snippet(n, q)),
    ];
  }

  String _snippet(Note note, String query) {
    final body = note.body ?? '';
    final idx = body.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      final t = note.title;
      return t.length > 80 ? '${t.substring(0, 80)}...' : t;
    }
    final start = (idx - 30).clamp(0, body.length);
    final end = (idx + query.length + 30).clamp(0, body.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < body.length ? '...' : '';
    return '$prefix${body.substring(start, end)}$suffix';
  }
}
