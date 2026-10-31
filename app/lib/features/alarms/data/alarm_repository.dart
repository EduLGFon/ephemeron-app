// Mirrors native registrations in alarms_index and rebuilds the rolling
// window from occurrence_cache plus timed tasks.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/alarms/alarm_window.dart';

import 'alarm_scheduler.dart';

class AlarmRepository {
  AlarmRepository(this._db);

  final AppDatabase _db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Rebuilds the rolling window: next 48 h plus next 60 future alarms.
  /// Called on app open, after occurrence rebuilds, and by the daily job.
  Future<int> rebuildWindow() async {
    final now = _now();
    final occs =
        await (_db.select(_db.occurrenceCache)
              ..where((c) => c.startUtc.isBiggerThanValue(now))
              ..orderBy([(c) => OrderingTerm.asc(c.startUtc)])
              ..limit(500))
            .get();
    final candidates = <AlarmCandidate>[];
    final seenEvents = <String>{};
    for (final o in occs) {
      if (!seenEvents.add(o.eventId)) continue;
      final e = await (_db.select(
        _db.events,
      )..where((ev) => ev.id.equals(o.eventId))).getSingleOrNull();
      if (e == null || e.deletedAt != null) continue;
      final preset = e.alarmPreset ?? 'medium';
      final offsets = _offsetsFor(preset);
      for (final off in offsets) {
        candidates.add(
          AlarmCandidate(
            sourceType: 'event',
            sourceId: '${e.id}@${o.startUtc}',
            fireAtUtcMs: o.startUtc - off * msPerMinute,
            preset: preset,
          ),
        );
      }
    }
    final timedTasks =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.completedAt.isNull() &
                  t.dueDate.isNotNull() &
                  t.dueTime.isNotNull(),
            ))
            .get();
    for (final t in timedTasks) {
      final p = t.dueDate!.split('-');
      final fire = DateTime.utc(
        int.parse(p[0]),
        int.parse(p[1]),
        int.parse(p[2]),
        t.dueTime! ~/ 60,
        t.dueTime! % 60,
      ).millisecondsSinceEpoch;
      candidates.add(
        AlarmCandidate(
          sourceType: 'task',
          sourceId: t.id,
          fireAtUtcMs: fire,
          preset: t.alarmPreset ?? 'medium',
        ),
      );
    }
    final planned = planAlarmWindow(candidates, nowUtcMs: now);
    await _db.transaction(() async {
      await _db.delete(_db.alarmsIndex).go();
      for (final p in planned) {
        await _db
            .into(_db.alarmsIndex)
            .insert(
              AlarmsIndexCompanion.insert(
                id: newId(),
                sourceType: p.sourceType,
                sourceId: p.sourceId,
                fireAtUtc: p.fireAtUtcMs,
                presetStep: const Value(null),
                requestCode: Value(p.requestCode),
                state: const Value('scheduled'),
              ),
            );
        await AlarmScheduler.schedule(
          requestCode: p.requestCode,
          fireAtUtcMs: p.fireAtUtcMs,
          useAlarmClock: needsAlarmClock(p.preset),
          title: p.sourceId,
          preset: p.preset,
          sourceType: p.sourceType,
          sourceId: p.sourceId,
        );
      }
    });
    return planned.length;
  }

  /// Reminder offsets in minutes for a preset (custom value supported).
  static List<int> _offsetsFor(String preset) {
    return switch (preset) {
      'light' => [10],
      'medium' => [10, 60],
      'strong' => [0, 30],
      'constant' => [0],
      'habit' => [0],
      _ => [10],
    };
  }

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

  Future<AlarmsIndexData?> latestFired() async {
    return (_db.select(_db.alarmsIndex)
          ..where((a) => a.state.equals('fired'))
          ..orderBy([(a) => OrderingTerm.desc(a.fireAtUtc)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> snoozeRequest(int requestCode, {int minutes = 10}) async {
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
    await AlarmScheduler.schedule(
      requestCode: requestCode,
      fireAtUtcMs: fireAt,
      useAlarmClock: false,
      title: 'Snoozed alarm',
    );
  }

  Future<void> markDone(int requestCode) async {
    await AlarmScheduler.cancel(requestCode);
    await (_db.update(_db.alarmsIndex)
          ..where((a) => a.requestCode.equals(requestCode)))
        .write(const AlarmsIndexCompanion(state: Value('done')));
  }
}
