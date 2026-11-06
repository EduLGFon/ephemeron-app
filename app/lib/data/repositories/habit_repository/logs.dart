part of '../habit_repository.dart';

mixin _HabitLogOps on _HabitRepositoryBase {
  Stream<List<HabitLog>> watchLogs(String habitId) {
    final q = _db.select(_db.habitLogs)
      ..where((l) => l.habitId.equals(habitId))
      ..orderBy([(l) => OrderingTerm.asc(l.dayKey)]);
    return q.watch();
  }

  Future<HabitLog?> logFor(String habitId, String dayKey) {
    return (_db.select(_db.habitLogs)
          ..where((l) => l.habitId.equals(habitId) & l.dayKey.equals(dayKey)))
        .getSingleOrNull();
  }

  Future<void> logDone(String habitId, String dayKey, {double? amount}) async {
    final existing = await logFor(habitId, dayKey);
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              amount: Value(amount ?? 0),
              done: const Value(true),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          done: const Value(true),
          skipped: const Value(false),
          amount: amount == null
              ? const Value.absent()
              : Value(existing.amount + amount),
          updatedAt: Value(nowMs()),
        ),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
    await cancelHabitDayAlarms(_db, habitId, dayKey);
  }

  /// Adds [amount] to the day's goal progress, creating the log if needed.
  /// Done and skipped are preserved; the log is marked done when a positive
  /// goal amount is reached.
  Future<void> addAmount(String habitId, String dayKey, double amount) async {
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    final goal = habit?.goalAmount ?? 0;
    final existing = await logFor(habitId, dayKey);
    final next = (existing?.amount ?? 0) + amount;
    final reachedDone = existing?.done == true || (goal > 0 && next >= goal);
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              amount: Value(next),
              done: Value(reachedDone),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value(next),
          done: Value(reachedDone),
          updatedAt: Value(nowMs()),
        ),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
    if (reachedDone) {
      await cancelHabitDayAlarms(_db, habitId, dayKey);
    }
  }

  Future<void> setSkipped(String habitId, String dayKey, bool skipped) async {
    final existing = await logFor(habitId, dayKey);
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              skipped: Value(skipped),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(skipped: Value(skipped), updatedAt: Value(nowMs())),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
  }

  Future<void> setDone(String habitId, String dayKey, bool done) async {
    final existing = await logFor(habitId, dayKey);
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              done: Value(done),
              skipped: Value(false),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          done: Value(done),
          skipped: done ? const Value(false) : const Value.absent(),
          updatedAt: Value(nowMs()),
        ),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
    if (done) {
      await cancelHabitDayAlarms(_db, habitId, dayKey);
    }
  }

  Future<void> toggleHabitDone(String habitId, String dayKey) async {
    final existing = await logFor(habitId, dayKey);
    if (existing != null && existing.done) {
      await setDone(habitId, dayKey, false);
    } else {
      await logDone(habitId, dayKey);
    }
  }

  Future<void> backfill(
    String habitId,
    String dayKey,
    double amount,
    bool done,
  ) async {
    final existing = await logFor(habitId, dayKey);
    if (existing == null) {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              amount: Value(amount),
              done: Value(done),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value(amount),
          done: Value(done),
          updatedAt: Value(nowMs()),
        ),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
  }
}
