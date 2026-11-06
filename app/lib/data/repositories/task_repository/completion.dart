part of '../task_repository.dart';

mixin _TaskCompletionOps on _TaskRepositoryBase {
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
  });

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
  });

  Future<List<String>> taskTagIds(String taskId);

  Future<void> completeTask(String id, {DateTime? at}) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    final completedMs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          completedAt: Value(completedMs),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      if (task.rrule != null && task.rrule!.isNotEmpty) {
        var next = nextTaskDueDate(
          currentDueUtc: _taskBaseUtc(task),
          completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            completedMs,
            isUtc: true,
          ),
          rrule: task.rrule,
          mode: task.repeatMode ?? 'from_due_date',
        );
        // Skip occurrence dates that already have a sibling row.
        while (next != null &&
            await _hasSiblingOccurrence(task.seriesId ?? id, dateKey(next))) {
          next = nextTaskDueDate(
            currentDueUtc: _taskBaseUtcForDate(next),
            completedAtUtc: next,
            rrule: task.rrule,
            mode: 'from_due_date',
          );
        }
        if (next != null) {
          final tagIds = await taskTagIds(id);
          final tagNames = <String>[];
          for (final tid in tagIds) {
            final tag = await (_db.select(
              _db.tags,
            )..where((g) => g.id.equals(tid))).getSingleOrNull();
            if (tag != null) tagNames.add(tag.name);
          }
          await createTask(
            title: task.title,
            listId: task.listId,
            notes: task.notes,
            priority: task.priority,
            dueDate: task.dueDate == null ? null : dateKey(next),
            plannedDate: _shiftPlannedDate(
              task.plannedDate,
              _shiftBaseDate(task),
              next,
            ),
            plannedStart: _shiftPlannedStart(
              task.plannedStart,
              _shiftBaseDate(task),
              next,
            ),
            plannedEnd: _shiftPlannedEnd(
              task.plannedEnd,
              _shiftBaseDate(task),
              next,
            ),
            seriesId: task.seriesId,
            recurrenceKey: dateKey(next),
            dueTime: task.dueDate == null
                ? null
                : ((next.hour == 0 && next.minute == 0)
                      ? null
                      : next.hour * 60 + next.minute),
            durationMin: task.durationMin,
            rrule: task.rrule,
            repeatMode: task.repeatMode,
            parentId: task.parentId,
            tags: tagNames,
            alarmPreset: task.alarmPreset,
            reminders: task.reminders,
          );
          // Set seriesId/recurrenceKey on the newly created row.
          // createTask sets them when rrule provided; but ensure seriesId preserved.
          // Already handled in createTask because rrule set.
        }
      }
    });
    await _enqueue('task', id, 'update');
    await cancelAlarmsForEntity(_db, id);
  }

  Future<void> markWontDo(String id, {DateTime? at}) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    final completedMs = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          wontDo: const Value(true),
          completedAt: Value(completedMs),
          updatedAt: Value(nowMs()),
          dirty: const Value(true),
        ),
      );
      if (task.rrule != null && task.rrule!.isNotEmpty) {
        var next = nextTaskDueDate(
          currentDueUtc: _taskBaseUtc(task),
          completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            completedMs,
            isUtc: true,
          ),
          rrule: task.rrule,
          mode: task.repeatMode ?? 'from_due_date',
        );
        while (next != null &&
            await _hasSiblingOccurrence(task.seriesId ?? id, dateKey(next))) {
          next = nextTaskDueDate(
            currentDueUtc: _taskBaseUtcForDate(next),
            completedAtUtc: next,
            rrule: task.rrule,
            mode: 'from_due_date',
          );
        }
        if (next != null) {
          final tagIds = await taskTagIds(id);
          final tagNames = <String>[];
          for (final tid in tagIds) {
            final tag = await (_db.select(
              _db.tags,
            )..where((g) => g.id.equals(tid))).getSingleOrNull();
            if (tag != null) tagNames.add(tag.name);
          }
          await createTask(
            title: task.title,
            listId: task.listId,
            notes: task.notes,
            priority: task.priority,
            dueDate: task.dueDate == null ? null : dateKey(next),
            plannedDate: _shiftPlannedDate(
              task.plannedDate,
              _shiftBaseDate(task),
              next,
            ),
            plannedStart: _shiftPlannedStart(
              task.plannedStart,
              _shiftBaseDate(task),
              next,
            ),
            plannedEnd: _shiftPlannedEnd(
              task.plannedEnd,
              _shiftBaseDate(task),
              next,
            ),
            seriesId: task.seriesId,
            recurrenceKey: dateKey(next),
            dueTime: task.dueDate == null
                ? null
                : ((next.hour == 0 && next.minute == 0)
                      ? null
                      : next.hour * 60 + next.minute),
            durationMin: task.durationMin,
            rrule: task.rrule,
            repeatMode: task.repeatMode,
            parentId: task.parentId,
            tags: tagNames,
            alarmPreset: task.alarmPreset,
            reminders: task.reminders,
          );
        }
      }
    });
    await _enqueue('task', id, 'update');
    await cancelAlarmsForEntity(_db, id);
  }

  Future<void> uncompleteTask(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        completedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('task', id, 'update');
  }

  /// Advances a recurring task to its next due date without completing.
  Future<void> skipOccurrence(String id) async {
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    if (task.rrule == null || task.rrule!.isEmpty) return;
    var base = _taskBaseUtc(task);
    var next = nextTaskDueDate(
      currentDueUtc: base,
      completedAtUtc: base,
      rrule: task.rrule,
      mode: 'from_due_date',
    );
    while (next != null &&
        await _hasSiblingOccurrence(task.seriesId ?? id, dateKey(next))) {
      base = _taskBaseUtcForDate(next);
      next = nextTaskDueDate(
        currentDueUtc: base,
        completedAtUtc: base,
        rrule: task.rrule,
        mode: 'from_due_date',
      );
    }
    if (next == null) return;
    final n = next;
    await updateTask(
      id,
      dueDate: () => task.dueDate == null ? null : dateKey(n),
      plannedDate: () =>
          _shiftPlannedDate(task.plannedDate, _shiftBaseDate(task), n),
      plannedStart: () =>
          _shiftPlannedStart(task.plannedStart, _shiftBaseDate(task), n),
      plannedEnd: () =>
          _shiftPlannedEnd(task.plannedEnd, _shiftBaseDate(task), n),
      dueTime: () => task.dueDate == null
          ? null
          : ((n.hour == 0 && n.minute == 0) ? null : n.hour * 60 + n.minute),
    );
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        seriesId: Value(task.seriesId),
        recurrenceKey: Value(dateKey(next)),
      ),
    );
  }
}
