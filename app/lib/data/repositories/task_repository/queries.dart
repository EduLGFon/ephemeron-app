part of '../task_repository.dart';

mixin _TaskQueryOps on _TaskRepositoryBase {
  Stream<List<Task>> watchOpen({String? listId}) {
    final q = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.completedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'task', ops: const {'delete'}),
            ) &
            (listId == null
                ? t.parentId.isNull()
                : t.listId.equals(listId) & t.parentId.isNull()),
      );
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.asc(t.dueDate),
      (t) => OrderingTerm.asc(t.sortOrder),
    ]);
    return q.watch();
  }

  Stream<List<Task>> watchTrash() {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNotNull() &
                t.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'task', ops: const {'purge'}),
                ),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  /// Global-search hits: open and completed tasks, newest first.
  Future<List<Task>> searchTasks(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty || _blank(q)) return [];
    final like = _like(q);
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'task', ops: const {'delete'}),
                ) &
                (t.title.like(like) | t.notes.like(like)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(limit))
        .get();
  }

  Future<List<Tag>> searchTags(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty || _blank(q)) return [];
    return (_db.select(_db.tags)
          ..where((t) => t.name.like(_like(q)))
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..limit(limit))
        .get();
  }

  Stream<List<Task>> watchCompleted({String? listId, int limit = 200}) {
    final q = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.completedAt.isNotNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'task', ops: const {'delete'}),
            ) &
            (listId == null ? const Constant(true) : t.listId.equals(listId)),
      );
    q
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(limit);
    return q.watch();
  }

  Stream<List<Task>> watchSubtasks(String parentId) {
    return (_db.select(_db.tasks)
          ..where(
            (t) =>
                t.parentId.equals(parentId) &
                t.deletedAt.isNull() &
                t.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'task', ops: const {'delete'}),
                ),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// Returns [done, total] for subtasks.
  Future<List<int>> subtaskProgress(String parentId) async {
    final subs = await (_db.select(
      _db.tasks,
    )..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())).get();
    return [subs.where((s) => s.completedAt != null).length, subs.length];
  }
}
