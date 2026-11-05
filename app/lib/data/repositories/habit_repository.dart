// Habits, sections, logs. Local-first; habits sync via backend changesets.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/domain/habits/habit_calendar_entry.dart';
import 'package:ephemeron/domain/habits/streaks.dart';

class HabitRepository {
  HabitRepository(this._db);
  final AppDatabase _db;

  Future<void> _enqueue(String entity, String entityId, String op) =>
      enqueueOutbox(_db, entity: entity, entityId: entityId, op: op);

  Future<String> createSection(String name) async {
    final id = newId();
    final now = nowMs();
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

  Stream<List<HabitLog>> watchLogs(String habitId) {
    final q = _db.select(_db.habitLogs)
      ..where((l) => l.habitId.equals(habitId))
      ..orderBy([(l) => OrderingTerm.asc(l.dayKey)]);
    return q.watch();
  }

  /// Reactive stream of scheduled habit entries with their log state for a
  /// date-key range (inclusive). One Drift query; reads habits + habitLogs.
  Stream<List<HabitCalendarEntry>> watchCalendarEntries(
    String fromKey,
    String toKey,
  ) {
    final query = _db.customSelect(
      'WITH RECURSIVE days(d) AS ('
      "SELECT ?1 UNION ALL SELECT date(d, '+1 day') FROM days WHERE d < ?2"
      ') '
      'SELECT h.id AS habit_id, h.name AS habit_name, '
      'h.frequency AS frequency, h.weekdays_mask AS weekdays_mask, '
      'h.weekly_target AS weekly_target, h.interval_days AS interval_days, '
      'h.start_date AS start_date, h.reminder_time AS reminder_time, '
      'h.unit AS unit, h.goal_amount AS goal_amount, '
      'h.increment AS increment, '
      'l.amount AS log_amount, l.done AS log_done, '
      'l.skipped AS log_skipped, days.d AS day '
      'FROM days CROSS JOIN habits h '
      'LEFT JOIN habit_logs l ON l.habit_id = h.id AND l.day_key = days.d '
      "WHERE h.archived = 0 AND h.deleted_at IS NULL "
      "AND h.id NOT IN (SELECT entity_id FROM outbox WHERE entity = 'habit' AND op = 'delete')",
      variables: [Variable<String>(fromKey), Variable<String>(toKey)],
      readsFrom: {_db.habits, _db.habitLogs, _db.outbox},
    );
    return query.watch().map((rows) {
      final out = <HabitCalendarEntry>[];
      for (final r in rows) {
        final day = r.read<String>('day');
        final spec = HabitSpec(
          frequency: r.read<String>('frequency'),
          weekdaysMask: r.read<int>('weekdays_mask'),
          weeklyTarget: r.readNullable<int>('weekly_target') ?? 0,
          intervalDays: r.readNullable<int>('interval_days') ?? 0,
          startDate: r.readNullable<String>('start_date'),
        );
        if (!isHabitScheduled(spec, parseKey(day))) continue;
        out.add(
          HabitCalendarEntry(
            habitId: r.read<String>('habit_id'),
            habitName: r.read<String>('habit_name'),
            dayKey: day,
            timeMinutes: parseHabitTimeMinutes(
              r.readNullable<String>('reminder_time'),
            ),
            unit: r.readNullable<String>('unit'),
            goalAmount: r.readNullable<double>('goal_amount'),
            increment: r.readNullable<double>('increment'),
            amount: r.readNullable<double>('log_amount') ?? 0,
            done: (r.readNullable<int>('log_done') ?? 0) == 1,
            skipped: (r.readNullable<int>('log_skipped') ?? 0) == 1,
          ),
        );
      }
      out.sort((a, b) {
        final c = a.dayKey.compareTo(b.dayKey);
        if (c != 0) return c;
        return a.habitName.compareTo(b.habitName);
      });
      return out;
    });
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
        updatedAt: Value(nowMs()),
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
    if (existing == null) {
      final next = amount;
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: newId(),
              habitId: habitId,
              dayKey: dayKey,
              amount: Value(next),
              done: Value(goal > 0 && next >= goal),
              createdAt: nowMs(),
              updatedAt: nowMs(),
            ),
          );
    } else {
      final next = existing.amount + amount;
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          amount: Value(next),
          done: Value(existing.done || (goal > 0 && next >= goal)),
          updatedAt: Value(nowMs()),
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

  Future<void> _touchHabit(String habitId) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(updatedAt: Value(nowMs()), dirty: const Value(true)),
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
