part of '../task_repository.dart';

mixin _TaskListOps on _TaskRepositoryBase {
  Future<List<String>> softDeleteTasks(List<String> ids);
  Future<Map<String, String?>> moveTasks(List<String> ids, String? listId);

  // Lists.

  Future<String> createList(String name, {String? color}) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: id,
            name: name,
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue('task_list', id, 'create');
    return id;
  }

  Stream<List<TaskList>> watchLists() {
    return (_db.select(_db.taskLists)
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
        .watch();
  }

  /// Persists a user-defined list order. Local-only: Google Tasks has no
  /// position field, so no outbox row is queued.
  Future<void> reorderLists(List<String> orderedIds) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.taskLists)
              ..where((l) => l.id.equals(orderedIds[i])))
            .write(TaskListsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Renames and/or recolors a list locally and queues the remote patch.
  /// Google Tasks lists have no color, so color stays device-local.
  Future<void> updateList(String id, {String? name, String? color}) async {
    final existing = await _list(id);
    if (existing == null || existing.deletedAt != null) return;
    if (name == null && color == null) return;
    await (_db.update(_db.taskLists)..where((l) => l.id.equals(id))).write(
      TaskListsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        color: color == null ? const Value.absent() : Value(color),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('task_list', id, 'update');
  }

  /// Soft-deletes [id]. Its tasks move to [moveTasksToListId] (null means the
  /// unlisted bucket) or, when [deleteTasks] is true, go to Trash with it.
  ///
  /// The list row is kept until the remote delete is pushed: deleting a
  /// remote-backed list only locally would resurrect it on the next discovery.
  Future<void> deleteList(
    String id, {
    String? moveTasksToListId,
    bool deleteTasks = false,
  }) async {
    final list = await _list(id);
    if (list == null || list.deletedAt != null) return;
    if (!deleteTasks && moveTasksToListId != null) {
      if (moveTasksToListId == id) {
        throw SourceMoveException('Choose another list.');
      }
      final target = await _list(moveTasksToListId);
      if (target == null || target.deletedAt != null) {
        throw SourceMoveException('Task list not found.');
      }
    }
    final rows = await (_db.select(
      _db.tasks,
    )..where((t) => t.listId.equals(id))).get();
    final ids = [for (final task in rows) task.id];
    if (deleteTasks) {
      final active = [
        for (final task in rows)
          if (task.deletedAt == null) task.id,
      ];
      if (active.isNotEmpty) await softDeleteTasks(active);
    } else if (ids.isNotEmpty) {
      await moveTasks(ids, moveTasksToListId);
    }
    await _db.transaction(() async {
      await (_db.update(_db.taskLists)..where((l) => l.id.equals(id))).write(
        TaskListsCompanion(
          deletedAt: Value(nowMs()),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      await _enqueue('task_list', id, 'delete');
    });
  }
}
