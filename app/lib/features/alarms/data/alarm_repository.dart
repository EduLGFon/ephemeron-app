// Mirrors native registrations in alarms_index and rebuilds the rolling
// window from occurrence_cache plus timed tasks, countdowns and habits.
// Reminders (kind=reminder, plain notification) never replace alarms
// (kind=alarm, one of the three AlarmPreset styles).
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/domain/alarms/alarm_preset.dart';
import 'package:ephemeron/domain/alarms/alarm_window.dart';
import 'package:ephemeron/domain/alarms/reminder.dart';

import 'alarm_scheduler.dart';

class AlarmRepository {
  AlarmRepository(this._db);

  final AppDatabase _db;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Rebuilds the rolling window: next 48 h plus next 60 future alarms.
  /// Called on app open, after occurrence rebuilds, and by the daily job.
  Future<int> rebuildWindow() async {
    final now = _now();
    final candidates = <AlarmCandidate>[
      ...await _eventCandidates(now),
      ...await _taskCandidates(),
      ...await _countdownCandidates(now),
      ...await _habitCandidates(now),
    ];
    final planned = planAlarmWindow(candidates, nowUtcMs: now);
    final existing = await _db.select(_db.alarmsIndex).get();
    final existingCodes = {
      for (final r in existing)
        if (r.requestCode != null) r.requestCode!,
    };
    final plannedCodes = {for (final p in planned) p.requestCode};
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
                kind: Value(p.kind),
                title: Value(p.title.isEmpty ? p.sourceId : p.title),
                preset: Value(p.preset),
              ),
            );
        final preset = AlarmPreset.tryParse(p.preset);
        if (p.kind == 'reminder') {
          await AlarmScheduler.scheduleReminder(
            requestCode: p.requestCode,
            fireAtUtcMs: p.fireAtUtcMs,
            title: p.title.isEmpty ? p.sourceId : p.title,
            sourceType: p.sourceType,
            sourceId: p.sourceId,
          );
        } else if (preset != null) {
          await AlarmScheduler.schedulePreset(
            requestCode: p.requestCode,
            fireAtUtcMs: p.fireAtUtcMs,
            preset: preset,
            title: p.title.isEmpty ? p.sourceId : p.title,
            sourceType: p.sourceType,
            sourceId: p.sourceId,
          );
        }
      }
    });
    for (final code in existingCodes.difference(plannedCodes)) {
      await AlarmScheduler.cancel(code);
    }
    return planned.length;
  }

  Future<List<AlarmCandidate>> _eventCandidates(int now) async {
    final occs =
        await (_db.select(_db.occurrenceCache)
              ..where((c) => c.startUtc.isBiggerThanValue(now - msPerDay))
              ..orderBy([(c) => OrderingTerm.asc(c.startUtc)])
              ..limit(500))
            .get();
    if (occs.isEmpty) return [];
    final eventIds = {for (final o in occs) o.eventId};
    final events = await (_db.select(
      _db.events,
    )..where((e) => e.id.isIn(eventIds.toList()))).get();
    final byId = {for (final e in events) e.id: e};
    final out = <AlarmCandidate>[];
    final seen = <String>{};
    for (final o in occs) {
      final e = byId[o.eventId];
      if (e == null || e.deletedAt != null) continue;
      final key = '${e.id}@${o.startUtc}';
      if (!seen.add(key)) continue;
      final title = e.title.isEmpty ? 'Event' : e.title;
      final offsets = parseReminderOffsets(e.reminders, allDay: e.isAllDay);
      final base = e.isAllDay ? _nineAmForDay(o.dayKey) : o.startUtc;
      for (final off in offsets) {
        out.add(
          AlarmCandidate(
            sourceType: 'event_reminder',
            sourceId: '$key#r$off',
            fireAtUtcMs: base - off * msPerMinute,
            preset: AlarmPreset.notification.id,
            kind: 'reminder',
            title: title,
          ),
        );
      }
      final preset = parseAlarmPreset(e.alarmPreset);
      if (preset != null) {
        out.add(
          AlarmCandidate(
            sourceType: 'event',
            sourceId: key,
            fireAtUtcMs: base,
            preset: preset.id,
            kind: 'alarm',
            title: title,
          ),
        );
      }
    }
    return out;
  }

  Future<List<AlarmCandidate>> _taskCandidates() async {
    final tasks =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.completedAt.isNull() &
                  t.dueDate.isNotNull(),
            ))
            .get();
    final out = <AlarmCandidate>[];
    for (final t in tasks) {
      final p = t.dueDate!.split('-');
      if (p.length != 3) continue;
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) continue;
      final mins = t.dueTime;
      final fire = mins == null
          ? DateTime.utc(y, m, d, 9).millisecondsSinceEpoch
          : DateTime.utc(y, m, d, mins ~/ 60, mins % 60).millisecondsSinceEpoch;
      final title = t.title.isEmpty ? 'Task' : t.title;
      out.add(
        AlarmCandidate(
          sourceType: 'task_reminder',
          sourceId: '${t.id}#at',
          fireAtUtcMs: fire,
          preset: AlarmPreset.notification.id,
          kind: 'reminder',
          title: title,
        ),
      );
      final preset = parseAlarmPreset(t.alarmPreset);
      if (preset != null && preset != AlarmPreset.notification) {
        out.add(
          AlarmCandidate(
            sourceType: 'task',
            sourceId: t.id,
            fireAtUtcMs: fire,
            preset: preset.id,
            kind: 'alarm',
            title: title,
          ),
        );
      }
    }
    return out;
  }

  Future<List<AlarmCandidate>> _countdownCandidates(int now) async {
    final rows = await (_db.select(
      _db.countdowns,
    )..where((c) => c.deletedAt.isNull())).get();
    final out = <AlarmCandidate>[];
    final today = DateTime.now();
    for (final c in rows) {
      if (c.targetDate == null || c.targetDate!.isEmpty) continue;
      final p = c.targetDate!.split('-');
      if (p.length != 3) continue;
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) continue;
      DateTime next;
      if (c.yearlyRepeat) {
        next = _nextYearly(m, d, today);
      } else {
        next = DateTime(y, m, d);
        if (next.isBefore(DateTime(today.year, today.month, today.day))) {
          continue;
        }
      }
      final timeMin = c.alertTimeMin ?? 540;
      DateTime atDay(DateTime day) => DateTime.utc(
        day.year,
        day.month,
        day.day,
        timeMin ~/ 60,
        timeMin % 60,
      );
      final title = c.title.isEmpty ? 'Countdown' : c.title;
      final offsets = <int>{0, c.alertOffsetDays ?? 3};
      for (final off in offsets) {
        final day = next.subtract(Duration(days: off));
        out.add(
          AlarmCandidate(
            sourceType: 'countdown_reminder',
            sourceId: '${c.id}@${off}d',
            fireAtUtcMs: atDay(day).millisecondsSinceEpoch,
            preset: AlarmPreset.notification.id,
            kind: 'reminder',
            title: title,
          ),
        );
      }
      final preset = parseAlarmPreset(c.alarmPreset);
      if (preset != null && preset != AlarmPreset.notification) {
        out.add(
          AlarmCandidate(
            sourceType: 'countdown',
            sourceId: c.id,
            fireAtUtcMs: atDay(next).millisecondsSinceEpoch,
            preset: preset.id,
            kind: 'alarm',
            title: title,
          ),
        );
      } else if (preset == AlarmPreset.notification) {
        // Notification-style alarm dedupes with the on-day reminder.
      }
    }
    return out;
  }

  Future<List<AlarmCandidate>> _habitCandidates(int now) async {
    final habits = await (_db.select(
      _db.habits,
    )..where((h) => h.archived.equals(false) & h.deletedAt.isNull())).get();
    final out = <AlarmCandidate>[];
    final localNow = DateTime.now();
    for (final h in habits) {
      if (h.reminderTime == null || h.reminderTime!.isEmpty) continue;
      final parts = h.reminderTime!.split(':');
      if (parts.length != 2) continue;
      final hh = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      if (hh == null || mm == null) continue;
      final title = h.name.isEmpty ? 'Habit' : h.name;
      for (var dayOff = 0; dayOff < 14; dayOff++) {
        final day = localNow.add(Duration(days: dayOff));
        final local = DateTime(day.year, day.month, day.day, hh, mm);
        final fireMs = local.toUtc().millisecondsSinceEpoch;
        if (fireMs <= now) continue;
        if (dayOff == 0 && await _habitDoneToday(h.id)) continue;
        out.add(
          AlarmCandidate(
            sourceType: 'habit_reminder',
            sourceId: '${h.id}@${local.year}-${local.month}-${local.day}',
            fireAtUtcMs: fireMs,
            preset: AlarmPreset.notification.id,
            kind: 'reminder',
            title: title,
          ),
        );
        final preset = parseAlarmPreset(h.alarmPreset);
        if (preset != null && preset != AlarmPreset.notification) {
          out.add(
            AlarmCandidate(
              sourceType: 'habit',
              sourceId: '${h.id}@${local.year}-${local.month}-${local.day}',
              fireAtUtcMs: fireMs,
              preset: preset.id,
              kind: 'alarm',
              title: title,
            ),
          );
        }
        break;
      }
    }
    return out;
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
      kind: 'alarm',
    );
  }

  Future<void> markDone(int requestCode) async {
    await AlarmScheduler.cancel(requestCode);
    await (_db.update(_db.alarmsIndex)
          ..where((a) => a.requestCode.equals(requestCode)))
        .write(const AlarmsIndexCompanion(state: Value('done')));
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
