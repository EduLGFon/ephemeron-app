part of '../habit_repository.dart';

mixin _HabitCrudOps on _HabitRepositoryBase {
  Future<String> createHabit({
    required String name,
    String? sectionId,
    String frequency = 'daily',
    int weekdaysMask = 0,
    int? weeklyTarget,
    int? intervalDays,
    String? goalType,
    double? goalAmount,
    String? unit,
    double? increment,
    int? goalDurationDays,
    String? startDate,
    String? reminderTime,
    String? alarmPreset,
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.habits)
        .insert(
          HabitsCompanion.insert(
            id: id,
            sectionId: Value(sectionId),
            name: name,
            frequency: Value(frequency),
            weekdaysMask: Value(weekdaysMask),
            weeklyTarget: Value(weeklyTarget),
            intervalDays: Value(intervalDays),
            goalType: Value(goalType),
            goalAmount: Value(goalAmount),
            unit: Value(unit),
            increment: Value(increment),
            goalDurationDays: Value(goalDurationDays),
            startDate: Value(startDate ?? habitDateKey(DateTime.now())),
            reminderTime: Value(reminderTime),
            alarmPreset: Value(alarmPreset),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await _enqueue('habit', id, 'create');
    return id;
  }

  Stream<List<Habit>> watchHabits({bool archived = false}) {
    final q = _db.select(_db.habits)
      ..where(
        (h) =>
            h.archived.equals(archived) &
            h.deletedAt.isNull() &
            h.id.isNotInQuery(
              pendingIdsQuery(
                _db,
                entity: 'habit',
                ops: {archived ? 'unarchive' : 'archive'},
              ),
            ) &
            h.id.isNotInQuery(
              pendingIdsQuery(_db, entity: 'habit', ops: const {'delete'}),
            ),
      );
    q.orderBy([(h) => OrderingTerm.asc(h.name)]);
    return q.watch();
  }

  /// Global-search hits over live habits.
  Future<List<Habit>> searchHabits(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = sanitizeSearch(q);
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    return (_db.select(_db.habits)
          ..where(
            (h) =>
                h.deletedAt.isNull() &
                h.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'habit', ops: const {'archive'}),
                ) &
                h.id.isNotInQuery(
                  pendingIdsQuery(_db, entity: 'habit', ops: const {'delete'}),
                ) &
                h.name.like(like),
          )
          ..orderBy([(h) => OrderingTerm.asc(h.name)])
          ..limit(limit))
        .get();
  }

  Future<void> archiveHabit(String id, bool archived) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        archived: Value(archived),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('habit', id, 'update');
  }

  Future<void> deleteHabit(String id) async {
    final now = nowMs();
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
    await _enqueue('habit', id, 'delete');
  }

  Future<void> restoreHabit(String id) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('habit', id, 'update');
  }

  HabitSpec specOf(Habit h) => HabitSpec(
    frequency: h.frequency,
    weekdaysMask: h.weekdaysMask,
    weeklyTarget: h.weeklyTarget ?? 0,
    intervalDays: h.intervalDays ?? 0,
    startDate: h.startDate,
  );

  Future<void> updateHabit(
    String id, {
    String? name,
    String? Function()? sectionId,
    String? frequency,
    int? weekdaysMask,
    int? Function()? weeklyTarget,
    int? Function()? intervalDays,
    String? Function()? goalType,
    double? Function()? goalAmount,
    String? Function()? unit,
    double? Function()? increment,
    int? Function()? goalDurationDays,
    String? startDate,
    String? Function()? reminderTime,
    String? Function()? alarmPreset,
  }) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        sectionId: sectionId == null
            ? const Value.absent()
            : Value(sectionId()),
        frequency: frequency == null ? const Value.absent() : Value(frequency),
        weekdaysMask: weekdaysMask == null
            ? const Value.absent()
            : Value(weekdaysMask),
        weeklyTarget: weeklyTarget == null
            ? const Value.absent()
            : Value(weeklyTarget()),
        intervalDays: intervalDays == null
            ? const Value.absent()
            : Value(intervalDays()),
        goalType: goalType == null ? const Value.absent() : Value(goalType()),
        goalAmount: goalAmount == null
            ? const Value.absent()
            : Value(goalAmount()),
        unit: unit == null ? const Value.absent() : Value(unit()),
        increment: increment == null
            ? const Value.absent()
            : Value(increment()),
        goalDurationDays: goalDurationDays == null
            ? const Value.absent()
            : Value(goalDurationDays()),
        startDate: startDate == null ? const Value.absent() : Value(startDate),
        reminderTime: reminderTime == null
            ? const Value.absent()
            : Value(reminderTime()),
        alarmPreset: alarmPreset == null
            ? const Value.absent()
            : Value(alarmPreset()),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('habit', id, 'update');
  }
}
