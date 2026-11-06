part of '../note_repository.dart';

mixin _NoteCrudOps on _NoteRepositoryBase {
  Future<void> refreshLinks(String noteId);

  Future<String> createNote({
    required String title,
    String? body,
    String? folderId,
    String? linkedEventId,
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            folderId: Value(folderId),
            title: Value(title),
            body: Value(body),
            linkedEventId: Value(linkedEventId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await refreshLinks(id);
    return id;
  }

  Future<Note?> getNote(String id) {
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Note?> watchNote(String id) {
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<void> updateNote(
    String id, {
    String? title,
    String? Function()? body,
    String? Function()? folderId,
  }) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: body == null ? const Value.absent() : Value(body()),
        folderId: folderId == null ? const Value.absent() : Value(folderId()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    if (body != null || title != null) await refreshLinks(id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        pinned: Value(pinned),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<String> duplicateNote(String id) async {
    final src = await getNote(id);
    if (src == null) throw StateError('note $id not found');
    return createNote(
      title: '${src.title} (copy)',
      body: src.body,
      folderId: src.folderId,
      linkedEventId: src.linkedEventId,
    );
  }

  Future<void> trashNote(String id) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(nowMs()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> restoreNote(String id) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<List<Note>> notesInFolder(String? folderId) {
    final q = _db.select(_db.notes)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
            ),
      );
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else {
      q.where((t) => t.folderId.equals(folderId));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return q.get();
  }

  Stream<List<Note>> watchNotesInFolder(String? folderId) {
    final q = _db.select(_db.notes)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
            ),
      );
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else {
      q.where((t) => t.folderId.equals(folderId));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return q.watch();
  }

  Future<List<Note>> notesForEvent(String eventId) {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.linkedEventId.equals(eventId) &
                t.deletedAt.isNull() &
                t.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
                ),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  /// Reactive variant of [notesForEvent] so event details can show a newly
  /// saved note without closing the sheet.
  Stream<List<Note>> watchNotesForEvent(String eventId) {
    return (_db.select(_db.notes)
          ..where(
            (t) =>
                t.linkedEventId.equals(eventId) &
                t.deletedAt.isNull() &
                t.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'note', ops: const {'trash'}),
                ),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  /// Overflow note for long event descriptions. Idempotent per event:
  /// returns the existing overflow note when present.
  Future<String?> ensureOverflowNote(String eventId, String fullText) async {
    final existing =
        await (_db.select(_db.notes)
              ..where(
                (t) => t.linkedEventId.equals(eventId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.body != fullText) {
        await updateNote(existing.id, body: () => fullText);
      }
      return existing.id;
    }
    return createNote(
      title: 'Event description',
      body: fullText,
      linkedEventId: eventId,
    );
  }

  Stream<List<Note>> watchTrash() {
    return (_db.select(_db.notes)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }
}
