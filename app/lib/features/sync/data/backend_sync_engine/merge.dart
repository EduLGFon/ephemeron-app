part of '../backend_sync_engine.dart';

mixin _BackendSyncMergeOps on _BackendSyncEngineBase {
  /// LWW merge that never overwrites locally dirty rows or newer rows.
  @override
  Future<void> _mergeHabit(Map<String, dynamic> m) async {
    final id = m['id'] as String?;
    if (id == null) return;
    final existing = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(id))).getSingleOrNull();
    if (existing != null &&
        (existing.dirty ||
            existing.updatedAt >= (m['updatedAt'] as int? ?? 0))) {
      return;
    }
    final sectionId = m['sectionId'] as String?;
    final sectionOk =
        sectionId == null ||
        await (_db.select(
              _db.habitSections,
            )..where((s) => s.id.equals(sectionId))).getSingleOrNull() !=
            null;
    final companion = HabitsCompanion(
      id: Value(id),
      sectionId: Value(sectionOk ? sectionId : null),
      name: Value((m['name'] as String?) ?? 'Habit'),
      frequency: Value((m['frequency'] as String?) ?? 'daily'),
      weekdaysMask: Value((m['weekdaysMask'] as int?) ?? 0),
      weeklyTarget: Value(m['weeklyTarget'] as int?),
      intervalDays: Value(m['intervalDays'] as int?),
      goalType: Value(m['goalType'] as String?),
      goalAmount: Value((m['goalAmount'] as num?)?.toDouble()),
      unit: Value(m['unit'] as String?),
      increment: Value((m['increment'] as num?)?.toDouble()),
      goalDurationDays: Value(m['goalDurationDays'] as int?),
      startDate: Value(m['startDate'] as String?),
      archived: Value((m['archived'] as bool?) ?? false),
      reminderTime: Value(m['reminderTime'] as String?),
      alarmPreset: Value(m['alarmPreset'] as String?),
      createdAt: Value((m['createdAt'] as int?) ?? _now()),
      updatedAt: Value((m['updatedAt'] as int?) ?? _now()),
      deletedAt: Value(m['deletedAt'] as int?),
      dirty: const Value(false),
    );
    await _db.into(_db.habits).insertOnConflictUpdate(companion);
  }

  @override
  Future<void> _mergeLog(Map<String, dynamic> m) async {
    final habitId = m['habitId'] as String?;
    final dayKey = m['dayKey'] as String?;
    if (habitId == null || dayKey == null) return;
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null) return;
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) => l.habitId.equals(habitId) & l.dayKey.equals(dayKey),
            ))
            .getSingleOrNull();
    final ts = (m['updatedAt'] as int?) ?? 0;
    if (existing != null && existing.updatedAt >= ts) return;
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: m['id'] as String? ?? '$habitId@$dayKey',
              habitId: habitId,
              dayKey: dayKey,
              amount: Value((m['amount'] as num?)?.toDouble() ?? 0),
              done: Value((m['done'] as bool?) ?? false),
              skipped: Value((m['skipped'] as bool?) ?? false),
              createdAt: (m['createdAt'] as int?) ?? _now(),
              updatedAt: ts,
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value((m['amount'] as num?)?.toDouble() ?? 0),
          done: Value((m['done'] as bool?) ?? false),
          skipped: Value((m['skipped'] as bool?) ?? false),
          updatedAt: Value(ts),
        ),
      );
    }
  }

  @override
  Future<void> _mergeFocus(Map<String, dynamic> m) async {
    final id = m['id'] as String?;
    if (id == null) return;
    final ts = (m['updatedAt'] as int?) ?? 0;
    final existing = await (_db.select(
      _db.focusSessions,
    )..where((f) => f.id.equals(id))).getSingleOrNull();
    if (existing != null && existing.updatedAt >= ts) return;
    await _db
        .into(_db.focusSessions)
        .insertOnConflictUpdate(
          FocusSessionsCompanion(
            id: Value(id),
            taskId: Value(m['taskId'] as String?),
            habitId: Value(m['habitId'] as String?),
            startUtc: Value((m['startUtc'] as int?) ?? ts),
            endUtc: Value(m['endUtc'] as int?),
            targetEndUtc: Value(m['targetEndUtc'] as int?),
            phase: Value(m['phase'] as String?),
            note: Value(m['note'] as String?),
            createdAt: Value((m['createdAt'] as int?) ?? _now()),
            updatedAt: Value(ts),
          ),
        );
  }
}
