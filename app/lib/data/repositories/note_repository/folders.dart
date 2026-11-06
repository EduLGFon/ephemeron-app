part of '../note_repository.dart';

mixin _NoteFolderOps on _NoteRepositoryBase {
  Stream<List<Folder>> watchFolders(String? parentId) {
    final q = _db.select(_db.folders)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'folder', ops: const {'delete'}),
            ),
      );
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.watch();
  }

  Stream<List<Folder>> watchChildFolders(String? parentId) =>
      watchFolders(parentId);

  Future<List<Folder>> childFolders(String? parentId) async {
    final q = _db.select(_db.folders)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'folder', ops: const {'delete'}),
            ),
      );
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.get();
  }

  Future<String> createFolder(String name, {String? parentId}) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            parentId: Value(parentId),
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Chain from filesystem root down to [folderId] (inclusive).
  Future<List<Folder>> breadcrumbs(String folderId) async {
    final chain = <Folder>[];
    String? cursor = folderId;
    while (cursor != null) {
      final f = await (_db.select(
        _db.folders,
      )..where((t) => t.id.equals(cursor!))).getSingleOrNull();
      if (f == null) break;
      chain.insert(0, f);
      cursor = f.parentId;
    }
    return chain;
  }

  /// Moves a folder; refuses moves into itself or its own descendants.
  Future<void> moveFolder(String folderId, String? newParentId) async {
    if (newParentId == folderId) return;
    if (newParentId != null) {
      final crumbs = await breadcrumbs(newParentId);
      if (crumbs.any((f) => f.id == folderId)) return;
    }
    await (_db.update(_db.folders)..where((t) => t.id.equals(folderId))).write(
      FoldersCompanion(parentId: Value(newParentId), updatedAt: Value(nowMs())),
    );
  }

  /// Deletes a folder: children are reparented to the deleted folder's
  /// parent and its notes follow the folder's notes destination.
  Future<void> deleteFolder(String folderId) async {
    final folder = await (_db.select(
      _db.folders,
    )..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.folders,
      )..where((t) => t.parentId.equals(folderId))).write(
        FoldersCompanion(
          parentId: Value(folder.parentId),
          updatedAt: Value(nowMs()),
        ),
      );
      await (_db.update(
        _db.notes,
      )..where((t) => t.folderId.equals(folderId))).write(
        NotesCompanion(
          folderId: Value(folder.parentId),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      await (_db.delete(_db.folders)..where((t) => t.id.equals(folderId))).go();
    });
  }
}
