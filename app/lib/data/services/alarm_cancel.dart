import 'package:drift/drift.dart';

import '../../features/alarms/data/alarm_scheduler.dart';
import '../drift/app_database.dart';

/// Cancels scheduled alarms for an entity id, matching exact id plus
/// reminder/instance suffixes (`id#...`, `id@...`).
Future<void> cancelAlarmsForEntity(AppDatabase db, String id) async {
  try {
    final rows =
        await (db.select(db.alarmsIndex)..where(
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
        try {
          await AlarmScheduler.cancel(code);
        } catch (_) {}
      }
      try {
        await (db.update(db.alarmsIndex)..where((a) => a.id.equals(row.id)))
            .write(const AlarmsIndexCompanion(state: Value('cancelled')));
      } catch (_) {}
    }
  } catch (_) {}
}

/// Cancels pending alarms for a habit on [dayKey] (YYYY-MM-DD local key)
/// so a snoozed/due alarm for that day does not recur, without removing
/// future days' reminders.
Future<void> cancelHabitDayAlarms(
  AppDatabase db,
  String habitId,
  String dayKey,
) async {
  final sourceId = '$habitId@$dayKey';
  for (final type in const ['habit', 'habit_reminder']) {
    try {
      final rows =
          await (db.select(db.alarmsIndex)..where(
                (a) =>
                    a.state.equals('scheduled') &
                    a.sourceType.equals(type) &
                    a.sourceId.equals(sourceId),
              ))
              .get();
      for (final row in rows) {
        final code = row.requestCode;
        if (code != null) {
          try {
            await AlarmScheduler.cancel(code);
          } catch (_) {}
        }
        try {
          await (db.update(db.alarmsIndex)..where((a) => a.id.equals(row.id)))
              .write(const AlarmsIndexCompanion(state: Value('cancelled')));
        } catch (_) {}
      }
    } catch (_) {}
  }
}
