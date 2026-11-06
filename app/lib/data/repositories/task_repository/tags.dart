part of '../task_repository.dart';

extension TaskRepositoryTags on TaskRepository {
  // Tags.
  Future<String> ensureTag(String name, {String? color}) async {
    final clean = name.trim().toLowerCase();
    final existing = await (_db.select(
      _db.tags,
    )..where((g) => g.name.equals(clean))).getSingleOrNull();
    if (existing != null) return existing.id;
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(
            id: id,
            name: clean,
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<Tag>> watchTags() {
    return (_db.select(
      _db.tags,
    )..orderBy([(g) => OrderingTerm.asc(g.name)])).watch();
  }

  Future<List<String>> taskTagIds(String taskId) async {
    final rows = await (_db.select(
      _db.taskTags,
    )..where((tt) => tt.taskId.equals(taskId))).get();
    return rows.map((r) => r.tagId).toList();
  }

  Future<void> setTaskTags(String taskId, List<String> names) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((tt) => tt.taskId.equals(taskId))).go();
      for (final n in names) {
        final tagId = await ensureTag(n);
        await _db
            .into(_db.taskTags)
            .insert(TaskTagsCompanion.insert(taskId: taskId, tagId: tagId));
      }
      await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(updatedAt: Value(nowMs())),
      );
    });
    await _enqueue('task', taskId, 'update');
  }
}
