part of '../alarm_repository.dart';

mixin _AlarmManagementOps on _AlarmRepositoryBase {
  Future<void> cancelForSource(String sourceType, String sourceId) async {
    final rows =
        await (_db.select(_db.alarmsIndex)..where(
              (a) =>
                  a.sourceType.equals(sourceType) & a.sourceId.equals(sourceId),
            ))
            .get();
    for (final r in rows) {
      if (r.requestCode != null) {
        await AlarmScheduler.cancel(r.requestCode!);
      }
    }
    await (_db.delete(_db.alarmsIndex)..where(
          (a) => a.sourceType.equals(sourceType) & a.sourceId.equals(sourceId),
        ))
        .go();
  }

  Stream<List<AlarmsIndexData>> watchMissed() {
    return (_db.select(_db.alarmsIndex)
          ..where((a) => a.state.equals('missed'))
          ..orderBy([(a) => OrderingTerm.desc(a.fireAtUtc)]))
        .watch();
  }

  Stream<List<AlarmsIndexData>> watchUpcoming({int limit = 20}) {
    return (_db.select(_db.alarmsIndex)
          ..where((a) => a.state.equals('scheduled'))
          ..orderBy([(a) => OrderingTerm.asc(a.fireAtUtc)])
          ..limit(limit))
        .watch();
  }

  Future<List<AlarmsIndexData>> dueAlarms() async {
    final now = _now();
    return (_db.select(_db.alarmsIndex)..where(
          (a) =>
              a.state.equals('scheduled') &
              a.fireAtUtc.isSmallerOrEqualValue(now),
        ))
        .get();
  }

  Future<void> markFired(String id) async {
    await (_db.update(_db.alarmsIndex)..where((a) => a.id.equals(id))).write(
      const AlarmsIndexCompanion(state: Value('fired')),
    );
  }

  Future<AlarmsIndexData?> latestFired() async {
    return (_db.select(_db.alarmsIndex)
          ..where((a) => a.state.equals('fired'))
          ..orderBy([(a) => OrderingTerm.desc(a.fireAtUtc)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> snoozeRequest(int requestCode, {int minutes = 10}) async {
    final row = await (_db.select(
      _db.alarmsIndex,
    )..where((a) => a.requestCode.equals(requestCode))).getSingleOrNull();
    final fireAt =
        DateTime.now().toUtc().millisecondsSinceEpoch + minutes * msPerMinute;
    await (_db.update(
      _db.alarmsIndex,
    )..where((a) => a.requestCode.equals(requestCode))).write(
      AlarmsIndexCompanion(
        fireAtUtc: Value(fireAt),
        state: const Value('scheduled'),
      ),
    );
    final preset = AlarmPreset.tryParse(row?.preset);
    await AlarmScheduler.schedule(
      requestCode: requestCode,
      fireAtUtcMs: fireAt,
      useAlarmClock: false,
      title: row?.title ?? 'Snoozed alarm',
      body: '',
      preset: row?.preset ?? AlarmPreset.notification.id,
      sourceType: row?.sourceType,
      sourceId: row?.sourceId,
      kind: row?.kind ?? 'alarm',
      fullScreen: preset?.usesFullScreen ?? false,
    );
  }

  Future<void> markDone(int requestCode) async {
    final row = await (_db.select(
      _db.alarmsIndex,
    )..where((a) => a.requestCode.equals(requestCode))).getSingleOrNull();
    await AlarmScheduler.cancel(requestCode);
    await (_db.update(_db.alarmsIndex)
          ..where((a) => a.requestCode.equals(requestCode)))
        .write(const AlarmsIndexCompanion(state: Value('done')));
    if (row != null) {
      await _completeSource(row.sourceType, row.sourceId);
    }
  }

  Future<void> completeHabitPlusOne(int requestCode) async {
    final row = await (_db.select(
      _db.alarmsIndex,
    )..where((a) => a.requestCode.equals(requestCode))).getSingleOrNull();
    await AlarmScheduler.cancel(requestCode);
    await (_db.update(_db.alarmsIndex)
          ..where((a) => a.requestCode.equals(requestCode)))
        .write(const AlarmsIndexCompanion(state: Value('done')));
    if (row == null) return;
    final st = row.sourceType;
    if (st != 'habit' && st != 'habit_reminder') return;
    final baseId = _baseSourceId(row.sourceId);
    final dayKey = _habitDayKey(row.sourceId);
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(baseId))).getSingleOrNull();
    final rawStep = habit?.increment;
    final step = (rawStep == null || rawStep == 0) ? 1.0 : rawStep;
    await HabitRepository(_db).addAmount(baseId, dayKey, step);
    await cancelHabitDayAlarms(_db, baseId, dayKey);
  }

  Future<void> _completeSource(String sourceType, String sourceId) async {
    final baseId = _baseSourceId(sourceId);
    try {
      if (sourceType == 'task' ||
          sourceType == 'task_reminder' ||
          sourceType == 'task_due_tomorrow') {
        final task = await (_db.select(
          _db.tasks,
        )..where((t) => t.id.equals(baseId))).getSingleOrNull();
        if (task == null || task.completedAt != null) return;
        await TaskRepository(_db).completeTask(baseId);
        await cancelAlarmsForEntity(_db, baseId);
        return;
      }
      if (sourceType == 'habit' || sourceType == 'habit_reminder') {
        final dayKey = _habitDayKey(sourceId);
        await HabitRepository(_db).logDone(baseId, dayKey);
        await cancelHabitDayAlarms(_db, baseId, dayKey);
      }
    } catch (_) {
      // Best effort: the alarm itself is already resolved.
    }
  }

  String _baseSourceId(String sourceId) {
    final at = sourceId.indexOf('@');
    if (at >= 0) return sourceId.substring(0, at);
    final hash = sourceId.indexOf('#');
    return hash >= 0 ? sourceId.substring(0, hash) : sourceId;
  }

  String _habitDayKey(String sourceId) {
    final at = sourceId.indexOf('@');
    if (at >= 0 && at + 1 < sourceId.length) return sourceId.substring(at + 1);
    return habitDateKey(DateTime.now());
  }

  Future<void> dismissRequest(int requestCode) async {
    await AlarmScheduler.cancel(requestCode);
    await (_db.update(_db.alarmsIndex)
          ..where((a) => a.requestCode.equals(requestCode)))
        .write(const AlarmsIndexCompanion(state: Value('dismissed')));
  }

  /// Cancels all pending alarms for a task entity (task, reminders,
  /// due-tomorrow). Safe for recurring tasks' completed row.
  Future<void> cancelForTask(String taskId) async {
    await _cancelByEntityPattern(taskId);
  }

  /// Cancels pending alarms for a habit on [dayKey] (YYYY-MM-DD local key)
  /// without removing future days' reminders.
  Future<void> cancelForHabitDay(String habitId, String dayKey) async {
    final sourceId = '$habitId@$dayKey';
    await cancelForSource('habit', sourceId);
    await cancelForSource('habit_reminder', sourceId);
  }

  Future<void> _cancelByEntityPattern(String id) async {
    final rows =
        await (_db.select(_db.alarmsIndex)..where(
              (a) =>
                  a.state.equals('scheduled') &
                  (a.sourceId.equals(id) |
                      a.sourceId.like('$id#%') |
                      a.sourceId.like('$id@%')),
            ))
            .get();
    for (final row in rows) {
      final code = row.requestCode;
      if (code != null) {
        await AlarmScheduler.cancel(code);
      }
      await (_db.update(_db.alarmsIndex)..where((a) => a.id.equals(row.id)))
          .write(const AlarmsIndexCompanion(state: Value('cancelled')));
    }
  }

  Future<void> markMissedBefore(int nowMs) async {
    await (_db.update(_db.alarmsIndex)..where(
          (a) =>
              a.state.equals('scheduled') &
              a.fireAtUtc.isSmallerThanValue(nowMs),
        ))
        .write(const AlarmsIndexCompanion(state: Value('missed')));
  }
}
