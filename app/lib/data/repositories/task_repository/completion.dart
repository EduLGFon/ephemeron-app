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

  String _shiftBaseDate(Task task) => task.dueDate ?? _baseDateKey(task);

  /// Recurring completion keeps the planned date offset from the due date.
  String? _shiftPlannedDate(
    String? plannedDate,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedDate == null || dueDate == null) return plannedDate;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final p = plannedDate.split('-');
    return dateKey(
      DateTime.utc(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]) + deltaDays,
      ),
    );
  }

  String? _shiftPlannedStart(
    String? plannedStart,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedStart == null || dueDate == null) return plannedStart;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final dt = DateTime.parse(plannedStart);
    final shifted = DateTime(
      dt.year,
      dt.month,
      dt.day + deltaDays,
      dt.hour,
      dt.minute,
    );
    return _formatLocalIso(shifted);
  }

  String? _shiftPlannedEnd(
    String? plannedEnd,
    String? dueDate,
    DateTime nextDue,
  ) {
    if (plannedEnd == null || dueDate == null) return plannedEnd;
    final nextKey = dateKey(nextDue);
    final deltaDays = _parseDateKey(
      nextKey,
    ).difference(_parseDateKey(dueDate)).inDays;
    final dt = DateTime.parse(plannedEnd);
    final shifted = DateTime(
      dt.year,
      dt.month,
      dt.day + deltaDays,
      dt.hour,
      dt.minute,
    );
    return _formatLocalIso(shifted);
  }

  String taskSeriesId(Task task) => task.seriesId ?? task.id;

  String currentTaskOccurrenceKey(Task task) =>
      task.recurrenceKey ??
      _effectiveOccurrenceDate(
        plannedStart: task.plannedStart,
        plannedDate: task.plannedDate,
        dueDate: task.dueDate,
      );

  /// Local-only per-occurrence completion for a projected/non-materialized
  /// occurrence. Does not touch the task row, dirty flag, or outbox.
  Future<void> completeTaskOccurrence(
    Task task,
    String occurrenceDate, {
    DateTime? at,
  }) async {
    await _setTaskOccurrenceState(
      task: task,
      occurrenceDate: occurrenceDate,
      status: 'completed',
      completedAt: (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    );
  }

  Future<void> markWontDoTaskOccurrence(
    Task task,
    String occurrenceDate, {
    DateTime? at,
  }) async {
    await _setTaskOccurrenceState(
      task: task,
      occurrenceDate: occurrenceDate,
      status: 'wont_do',
      completedAt: (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    );
  }

  Future<void> uncompleteTaskOccurrence(
    Task task,
    String occurrenceDate,
  ) async {
    final seriesId = taskSeriesId(task);
    await (_db.delete(_db.taskOccurrenceStates)..where(
          (s) =>
              s.seriesId.equals(seriesId) &
              s.occurrenceDate.equals(occurrenceDate),
        ))
        .go();
  }

  Future<void> _setTaskOccurrenceState({
    required Task task,
    required String occurrenceDate,
    required String status,
    int? completedAt,
  }) async {
    final seriesId = taskSeriesId(task);
    await _db
        .into(_db.taskOccurrenceStates)
        .insertOnConflictUpdate(
          TaskOccurrenceStatesCompanion.insert(
            seriesId: seriesId,
            occurrenceDate: occurrenceDate,
            status: status,
            completedAt: Value(completedAt),
            updatedAt: nowMs(),
          ),
        );
  }

  Future<bool> _hasSiblingOccurrence(
    String seriesId,
    String occurrenceDate,
  ) async {
    final rows =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.seriesId.equals(seriesId) &
                  t.recurrenceKey.equals(occurrenceDate) &
                  t.deletedAt.isNull(),
            ))
            .get();
    return rows.isNotEmpty;
  }

  DateTime _taskBaseUtc(Task task) {
    if (task.dueDate != null) {
      final p = task.dueDate!.split('-');
      final mins = task.dueTime ?? 0;
      return DateTime.utc(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
        mins ~/ 60,
        mins % 60,
      );
    }
    if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
      return DateTime.parse(task.plannedStart!).toUtc();
    }
    if (task.plannedDate != null) {
      final p = task.plannedDate!.split('-');
      return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    }
    return DateTime.now().toUtc();
  }

  String _baseDateKey(Task task) {
    if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
      return task.plannedStart!.substring(0, 10);
    }
    if (task.plannedDate != null) return task.plannedDate!;
    if (task.dueDate != null) return task.dueDate!;
    return dateKey(DateTime.now());
  }
}
