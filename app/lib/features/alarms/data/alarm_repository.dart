// Mirrors native registrations in alarms_index and rebuilds the rolling
// window from occurrence_cache plus timed tasks, countdowns and habits.
// Reminders (kind=reminder, plain notification) never replace alarms
// (kind=alarm, one of the three AlarmPreset styles).
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/data/services/alarm_cancel.dart';
import 'package:ephemeron/domain/alarms/alarm_preset.dart';
import 'package:ephemeron/domain/alarms/alarm_window.dart';
import 'package:ephemeron/domain/alarms/reminder.dart';
import 'package:ephemeron/domain/habits/date_key.dart';

import 'alarm_scheduler.dart';

part 'alarm_repository/rebuild.dart';
part 'alarm_repository/management.dart';

class _AlarmRepositoryBase {
  _AlarmRepositoryBase(this._db);

  final AppDatabase _db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  int _nineAmForDay(String dayKey) {
    final p = dayKey.split('-');
    if (p.length != 3) return _now();
    final y = int.tryParse(p[0]) ?? 2000;
    final m = int.tryParse(p[1]) ?? 1;
    final d = int.tryParse(p[2]) ?? 1;
    return DateTime(y, m, d, 9).toUtc().millisecondsSinceEpoch;
  }

  DateTime _nextYearly(int month, int day, DateTime today) {
    DateTime cand(int y) {
      final last = DateTime(y, month + 1, 0).day;
      return DateTime(y, month, day > last ? last : day);
    }

    var next = cand(today.year);
    if (next.isBefore(DateTime(today.year, today.month, today.day))) {
      next = cand(today.year + 1);
    }
    return next;
  }

  Future<bool> _habitDoneToday(String habitId) async {
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final log =
        await (_db.select(_db.habitLogs)
              ..where((l) => l.habitId.equals(habitId) & l.dayKey.equals(key)))
            .getSingleOrNull();
    return log?.done ?? false;
  }

  static DateTime clampDueTomorrow(DateTime localFire) {
    var dt = localFire;
    final tod = dt.hour * 60 + dt.minute;
    if (tod < 9 * 60) {
      dt = DateTime(dt.year, dt.month, dt.day, 9, 0);
    } else if (tod > 17 * 60) {
      dt = DateTime(dt.year, dt.month, dt.day, 17, 0);
    }
    return dt;
  }
}

class AlarmRepository extends _AlarmRepositoryBase
    with _AlarmRebuildOps, _AlarmManagementOps {
  AlarmRepository(super._db);

  static DateTime clampDueTomorrow(DateTime localFire) =>
      _AlarmRepositoryBase.clampDueTomorrow(localFire);
}
