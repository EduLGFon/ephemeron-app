// Habits, sections, logs. Local-first; habits sync via backend changesets.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/domain/habits/streaks.dart';

class HabitRepository {
  HabitRepository(this._db);
  final AppDatabase _db;
  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<void> _enqueue(String entity, String entityId, String op) {
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: newId(),
            entity: entity,
            entityId: entityId,
            op: op,
            createdAt: _now(),
          ),
        );
  }

  Future<String> createSection(String name) async {
    final id = newId();
    final now = _now();
    await _db
        .into(_db.habitSections)
        .insert(
          HabitSectionsCompanion.insert(
            id: id,
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Stream<List<HabitSection>> watchSections() {
    return (_db.select(
      _db.habitSections,
    )..orderBy([(s) => OrderingTerm.asc(s.sortOrder)])).watch();
  }

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
    final now = _now();
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
      ..where((h) => h.archived.equals(archived) & h.deletedAt.isNull());
    q.orderBy([(h) => OrderingTerm.asc(h.name)]);
    return q.watch();
  }

  Future<void> archiveHabit(String id, bool archived) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        archived: Value(archived),
        updatedAt: Value(_now()),
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

  Stream<List<HabitLog>> watchLogs(String habitId) {
    final q = _db.select(_db.habitLogs)
      ..where((l) => l.habitId.equals(habitId))
      ..orderBy([(l) => OrderingTerm.asc(l.dayKey)]);
    return q.watch();
  }

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
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
    await _enqueue('habit', id, 'update');
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
              createdAt: _now(),
              updatedAt: _now(),
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
          updatedAt: Value(_now()),
        ),
      );
    }
    await _enqueue('habit_log:$habitId', '$habitId@$dayKey', 'update');
    await _touchHabit(habitId);
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
              createdAt: _now(),
              updatedAt: _now(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(skipped: Value(skipped), updatedAt: Value(_now())),
      );
    }
    await _touchHabit(habitId);
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
              createdAt: _now(),
              updatedAt: _now(),
            ),
          );
    } else {
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value(amount),
          done: Value(done),
          updatedAt: Value(_now()),
        ),
      );
    }
    await _touchHabit(habitId);
  }

  Future<void> _touchHabit(String habitId) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(updatedAt: Value(_now()), dirty: const Value(true)),
    );
  }

  Future<({int current, int best})> streaks(
    String habitId,
    String todayKey,
  ) async {
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    if (habit == null) return (current: 0, best: 0);
    final logs = await (_db.select(
      _db.habitLogs,
    )..where((l) => l.habitId.equals(habitId))).get();
    final spec = specOf(habit);
    bool isDone(String day) {
      for (final l in logs) {
        if (l.dayKey != day) continue;
        if (l.done) return true;
        if ((habit.goalAmount ?? 0) > 0 && l.amount >= habit.goalAmount!) {
          return true;
        }
      }
      return false;
    }

    bool isSkipped(String day) {
      for (final l in logs) {
        if (l.dayKey == day && l.skipped) return true;
      }
      return false;
    }

    return (
      current: currentStreak(spec, todayKey, isDone, isSkipped),
      best: bestStreak(spec, todayKey, isDone, isSkipped),
    );
  }

  Future<double> weeklyRate(String habitId, String todayKey) async {
    final today = parseKey(todayKey);
    var done = 0, total = 0;
    for (var i = 0; i < 7; i++) {
      final key = habitDateKey(today.subtract(Duration(days: i)));
      final log = await logFor(habitId, key);
      if (log == null) continue;
      total++;
      if (log.done) done++;
    }
    if (total == 0) return 0;
    return done / total;
  }
}
