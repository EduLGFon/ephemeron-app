// Habits, sections, logs. Local-first; habits sync via backend changesets.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/data/services/alarm_cancel.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/domain/habits/habit_calendar_entry.dart';
import 'package:ephemeron/domain/habits/streaks.dart';

part 'habit_repository/sections.dart';
part 'habit_repository/habits.dart';
part 'habit_repository/calendar.dart';
part 'habit_repository/logs.dart';
part 'habit_repository/stats.dart';

class _HabitRepositoryBase {
  _HabitRepositoryBase(this._db);

  final AppDatabase _db;

  Future<void> _enqueue(String entity, String entityId, String op) =>
      enqueueOutbox(_db, entity: entity, entityId: entityId, op: op);

  Future<void> _touchHabit(String habitId) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(updatedAt: Value(nowMs()), dirty: const Value(true)),
    );
  }
}

class HabitRepository extends _HabitRepositoryBase
    with
        _HabitSectionOps,
        _HabitCrudOps,
        _HabitCalendarOps,
        _HabitLogOps,
        _HabitStatsOps {
  HabitRepository(super._db);
}
