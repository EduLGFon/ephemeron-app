part of '../task_repository.dart';

extension TaskRepositorySmartLists on TaskRepository {
  // Smart lists.
  Future<String> createSmartList(
    String name,
    Map<String, Object?> filter,
  ) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.smartLists)
        .insert(
          SmartListsCompanion.insert(
            id: id,
            name: name,
            filterJson: Value(jsonEncode(filter)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<SmartList>> watchSmartLists() {
    return (_db.select(
      _db.smartLists,
    )..orderBy([(s) => OrderingTerm.asc(s.name)])).watch();
  }

  Future<void> updateSmartList(
    String id, {
    String? name,
    Map<String, Object?>? filter,
  }) async {
    await (_db.update(_db.smartLists)..where((s) => s.id.equals(id))).write(
      SmartListsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        filterJson: filter == null
            ? const Value.absent()
            : Value(jsonEncode(filter)),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<void> deleteSmartList(String id) async {
    await (_db.delete(_db.smartLists)..where((s) => s.id.equals(id))).go();
  }

  /// Reactive view of a smart list. Unknown or malformed filter keys are
  /// ignored by [SmartFilter.fromMap].
  Stream<List<Task>> watchSmartList(Map<String, Object?> filter) {
    return _smartQuery(filter).watch();
  }

  /// Evaluates a smart-list filter. See [SmartFilter] for supported keys.
  Future<List<Task>> evalSmartList(Map<String, Object?> filter) {
    return _smartQuery(filter).get();
  }

  SimpleSelectStatement<$TasksTable, Task> _smartQuery(
    Map<String, Object?> rawFilter,
  ) {
    final filter = SmartFilter.fromMap(rawFilter);
    final q = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'task', ops: const {'delete'}),
            ),
      );
    if (!filter.showCompleted) {
      q.where((t) => t.completedAt.isNull());
    }
    if (filter.listIds.isNotEmpty) {
      q.where((t) => t.listId.isIn(filter.listIds));
    }
    if (filter.priorities.isNotEmpty) {
      q.where((t) => t.priority.isIn(filter.priorities));
    }
    final range = filter.dueRange();
    if (range.from != null) {
      q.where((t) => t.dueDate.isBiggerOrEqualValue(range.from!));
    }
    if (range.to != null) {
      q.where((t) => t.dueDate.isSmallerOrEqualValue(range.to!));
    }
    if (filter.tagIds.isNotEmpty) {
      final tagged = _db.selectOnly(_db.taskTags)
        ..addColumns([_db.taskTags.taskId])
        ..where(_db.taskTags.tagId.isIn(filter.tagIds));
      q.where((t) => t.id.isInQuery(tagged));
    }
    final query = sanitizeSearch(filter.query);
    if (query.isNotEmpty) {
      final like = '%$query%';
      q.where((t) => t.title.like(like) | t.notes.like(like));
    }
    q.orderBy(switch (filter.sort) {
      SmartSort.due => [
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.asc(t.dueDate),
        (t) => OrderingTerm.asc(t.sortOrder),
        (t) => OrderingTerm.asc(t.id),
      ],
      SmartSort.priority => [
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.priority),
        (t) => OrderingTerm.asc(t.dueDate),
        (t) => OrderingTerm.asc(t.id),
      ],
      SmartSort.created => [
        (t) => OrderingTerm.desc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ],
      SmartSort.title => [
        (t) => OrderingTerm.asc(t.title),
        (t) => OrderingTerm.asc(t.id),
      ],
    });
    return q;
  }
}
