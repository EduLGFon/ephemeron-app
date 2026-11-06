part of '../task_repository.dart';

mixin _TaskTrashOps on _TaskRepositoryBase {
  /// Soft-deletes; returns ids for undo snackbars.
  Future<List<String>> softDeleteTasks(List<String> ids) async {
    final now = nowMs();
    await (_db.update(_db.tasks)..where((t) => t.id.isIn(ids))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    for (final id in ids) {
      await _enqueue('task', id, 'delete');
    }
    return ids;
  }

  Future<void> restoreTasks(List<String> ids) async {
    await (_db.update(_db.tasks)..where((t) => t.id.isIn(ids))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    for (final id in ids) {
      await _enqueue('task', id, 'update');
    }
  }

  /// Permanent delete of one trashed task.
  Future<void> purgeTask(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((tt) => tt.taskId.equals(id))).go();
      await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Ids of trashed items older than [olderThanDays] (default 30).
  Future<List<String>> oldTrashIds({int olderThanDays = 30}) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: olderThanDays))
        .millisecondsSinceEpoch;
    final old =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNotNull() &
                  t.deletedAt.isSmallerThanValue(cutoff),
            ))
            .get();
    return [for (final t in old) t.id];
  }

  /// Purges items deleted more than [olderThanDays] ago (default 30).
  Future<int> emptyTrash({int olderThanDays = 30}) async {
    final ids = await oldTrashIds(olderThanDays: olderThanDays);
    for (final id in ids) {
      await purgeTask(id);
    }
    return ids.length;
  }
}
