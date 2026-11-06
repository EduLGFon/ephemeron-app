part of '../task_repository.dart';

extension TaskRepositoryTasks on TaskRepository {
  // Tasks.
  Future<String> createTask({
    required String title,
    String? listId,
    String? notes,
    int priority = 0,
    String? dueDate,
    String? plannedDate,
    String? plannedStart,
    String? plannedEnd,
    String? seriesId,
    String? recurrenceKey,
    int? dueTime,
    int? durationMin,
    String? rrule,
    String? repeatMode,
    String? parentId,
    bool pinned = false,
    List<String> tags = const [],
    String? alarmPreset,
    String? reminders,
  }) async {
    final id = newId();
    final now = nowMs();
    var list = listId;
    list ??= await _defaultListId();
    final account = await _accountOfList(list);
    String? sid = seriesId;
    String? rkey = recurrenceKey;
    if (rrule != null && rrule.isNotEmpty) {
      sid ??= id;
      rkey ??= _effectiveOccurrenceDate(
        plannedStart: plannedStart,
        plannedDate: plannedDate,
        dueDate: dueDate,
      );
    }
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: Value(title),
            listId: Value(list),
            notes: Value(notes),
            priority: Value(priority),
            dueDate: Value(dueDate),
            plannedDate: Value(plannedDate),
            plannedStart: Value(plannedStart),
            plannedEnd: Value(plannedEnd),
            seriesId: Value(sid),
            recurrenceKey: Value(rkey),
            dueTime: Value(dueTime),
            durationMin: Value(durationMin),
            rrule: Value(rrule),
            repeatMode: Value(repeatMode ?? 'from_due_date'),
            parentId: Value(parentId),
            pinned: Value(pinned),
            alarmPreset: Value(alarmPreset),
            reminders: Value(reminders),
            dirty: const Value(true),
            googleAccount: Value(account),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (tags.isNotEmpty) await setTaskTags(id, tags);
    await _enqueue('task', id, 'create');
    return id;
  }

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

  /// Persists a user-defined task order. Local-only: Google Tasks has no
  /// position field, so no outbox row is queued.
  Future<void> reorderTasks(List<String> orderedIds) async {
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.tasks)..where((t) => t.id.equals(orderedIds[i])))
            .write(TasksCompanion(sortOrder: Value(i)));
      }
    });
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

  Future<void> updateTask(
    String id, {
    String? title,
    String? notes,
    int? priority,
    String? Function()? dueDate,
    String? Function()? plannedDate,
    String? Function()? plannedStart,
    String? Function()? plannedEnd,
    int? Function()? dueTime,
    int? Function()? durationMin,
    String? Function()? rrule,
    String? listId,
    bool? pinned,
    bool? wontDo,
    int? sortOrder,
    String? Function()? alarmPreset,
    String? Function()? reminders,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title),
        notes: notes == null ? const Value.absent() : Value(notes),
        priority: priority == null ? const Value.absent() : Value(priority),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate()),
        plannedDate: plannedDate == null
            ? const Value.absent()
            : Value(plannedDate()),
        plannedStart: plannedStart == null
            ? const Value.absent()
            : Value(plannedStart()),
        plannedEnd: plannedEnd == null
            ? const Value.absent()
            : Value(plannedEnd()),
        dueTime: dueTime == null ? const Value.absent() : Value(dueTime()),
        durationMin: durationMin == null
            ? const Value.absent()
            : Value(durationMin()),
        rrule: rrule == null ? const Value.absent() : Value(rrule()),
        listId: listId == null ? const Value.absent() : Value(listId),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        wontDo: wontDo == null ? const Value.absent() : Value(wontDo),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
        alarmPreset: alarmPreset == null
            ? const Value.absent()
            : Value(alarmPreset()),
        reminders: reminders == null
            ? const Value.absent()
            : Value(reminders()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('task', id, 'update');
  }
}
