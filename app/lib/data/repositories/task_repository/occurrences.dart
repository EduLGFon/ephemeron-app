part of '../task_repository.dart';

mixin _TaskOccurrenceOps on _TaskRepositoryBase {
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
    await cancelAlarmsForEntity(_db, task.id);
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
    await cancelAlarmsForEntity(_db, task.id);
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
}
