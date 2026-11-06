part of '../backend_sync_engine.dart';

mixin _BackendSyncPushOps on _BackendSyncEngineBase {
  @override
  Future<void> _push(BackendSyncApi api) async {
    final dirtyHabits =
        await (_db.select(_db.habits)
              ..where((h) => h.dirty.equals(true))
              ..orderBy([(h) => OrderingTerm.asc(h.updatedAt)])
              ..limit(_BackendSyncEngineBase.batchLimit))
            .get();
    final logsCursor = await _cursor(_BackendSyncEngineBase._logsCursorKey);
    final dirtyLogs =
        await (_db.select(_db.habitLogs)
              ..where((l) => l.updatedAt.isBiggerThanValue(logsCursor))
              ..orderBy([(l) => OrderingTerm.asc(l.updatedAt)])
              ..limit(_BackendSyncEngineBase.batchLimit))
            .get();
    final focusCursor = await _cursor(_BackendSyncEngineBase._focusCursorKey);
    final dirtyFocus =
        await (_db.select(_db.focusSessions)
              ..where((f) => f.updatedAt.isBiggerThanValue(focusCursor))
              ..orderBy([(f) => OrderingTerm.asc(f.updatedAt)])
              ..limit(_BackendSyncEngineBase.batchLimit))
            .get();
    if (dirtyHabits.isEmpty && dirtyLogs.isEmpty && dirtyFocus.isEmpty) return;

    await api.push(
      habits: [for (final h in dirtyHabits) _habitJson(h)],
      habitLogs: [for (final l in dirtyLogs) _logJson(l)],
      focusSessions: [for (final f in dirtyFocus) _focusJson(f)],
    );

    if (dirtyHabits.isNotEmpty) {
      final maxTs = dirtyHabits
          .map((h) => h.updatedAt)
          .reduce((a, b) => a > b ? a : b);
      final ids = dirtyHabits.map((h) => h.id).toList();
      await (_db.update(_db.habits)..where(
            (h) => h.id.isIn(ids) & h.updatedAt.isSmallerOrEqualValue(maxTs),
          ))
          .write(const HabitsCompanion(dirty: Value(false)));
      for (final id in ids) {
        await (_db.delete(_db.outbox)..where(
              (o) =>
                  (o.entity.equals('habit') & o.entityId.equals(id)) |
                  o.entity.equals('habit_log:$id'),
            ))
            .go();
      }
    }
    if (dirtyLogs.isNotEmpty) {
      await _setCursor(
        _BackendSyncEngineBase._logsCursorKey,
        dirtyLogs.map((l) => l.updatedAt).reduce((a, b) => a > b ? a : b),
      );
    }
    if (dirtyFocus.isNotEmpty) {
      await _setCursor(
        _BackendSyncEngineBase._focusCursorKey,
        dirtyFocus.map((f) => f.updatedAt).reduce((a, b) => a > b ? a : b),
      );
    }
  }

  Map<String, dynamic> _habitJson(Habit h) => {
    'id': h.id,
    'sectionId': h.sectionId,
    'name': h.name,
    'frequency': h.frequency,
    'weekdaysMask': h.weekdaysMask,
    'weeklyTarget': h.weeklyTarget,
    'intervalDays': h.intervalDays,
    'goalType': h.goalType,
    'goalAmount': h.goalAmount,
    'unit': h.unit,
    'increment': h.increment,
    'goalDurationDays': h.goalDurationDays,
    'startDate': h.startDate,
    'archived': h.archived,
    'reminderTime': h.reminderTime,
    'alarmPreset': h.alarmPreset,
    'createdAt': h.createdAt,
    'updatedAt': h.updatedAt,
    'deletedAt': h.deletedAt,
  };

  Map<String, dynamic> _logJson(HabitLog l) => {
    'id': l.id,
    'habitId': l.habitId,
    'dayKey': l.dayKey,
    'amount': l.amount,
    'done': l.done,
    'skipped': l.skipped,
    'createdAt': l.createdAt,
    'updatedAt': l.updatedAt,
  };

  Map<String, dynamic> _focusJson(FocusSession f) => {
    'id': f.id,
    'taskId': f.taskId,
    'habitId': f.habitId,
    'startUtc': f.startUtc,
    'endUtc': f.endUtc,
    'targetEndUtc': f.targetEndUtc,
    'phase': f.phase,
    'note': f.note,
    'createdAt': f.createdAt,
    'updatedAt': f.updatedAt,
  };
}
