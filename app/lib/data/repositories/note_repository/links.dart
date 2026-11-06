part of '../note_repository.dart';

mixin _NoteLinkOps on _NoteRepositoryBase {
  Future<Note?> getNote(String id);

  /// Rebuilds outgoing links for [noteId] from its current body.
  Future<void> refreshLinks(String noteId) async {
    final note = await getNote(noteId);
    if (note == null) return;
    final titles = NoteRepository.extractLinkedTitles(note.body);
    await _db.transaction(() async {
      await (_db.delete(
        _db.noteLinks,
      )..where((t) => t.fromNoteId.equals(noteId))).go();
      for (final title in titles) {
        final target =
            await (_db.select(_db.notes)
                  ..where((t) => t.title.equals(title) & t.deletedAt.isNull()))
                .getSingleOrNull();
        if (target != null && target.id != noteId) {
          await _db
              .into(_db.noteLinks)
              .insert(
                NoteLinksCompanion.insert(
                  fromNoteId: noteId,
                  toNoteId: target.id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    });
  }

  /// Notes linking TO [noteId] (excludes trashed).
  Future<List<Note>> backlinks(String noteId) async {
    final rows = await (_db.select(
      _db.noteLinks,
    )..where((t) => t.toNoteId.equals(noteId))).get();
    final ids = rows.map((r) => r.fromNoteId).toSet();
    if (ids.isEmpty) return [];
    return (_db.select(_db.notes)..where(
          (t) =>
              t.id.isIn(ids) &
              t.deletedAt.isNull() &
              t.id.isNotInQuery(
                pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
              ),
        ))
        .get();
  }

  /// Notes that [noteId] links to (excludes trashed).
  Future<List<Note>> forwardLinks(String noteId) async {
    final rows = await (_db.select(
      _db.noteLinks,
    )..where((t) => t.fromNoteId.equals(noteId))).get();
    final ids = rows.map((r) => r.toNoteId).toSet();
    if (ids.isEmpty) return [];
    return (_db.select(_db.notes)..where(
          (t) =>
              t.id.isIn(ids) &
              t.deletedAt.isNull() &
              t.id.isNotInQuery(
                pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
              ),
        ))
        .get();
  }
}
