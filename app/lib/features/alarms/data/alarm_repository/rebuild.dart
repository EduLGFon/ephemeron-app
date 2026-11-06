part of '../alarm_repository.dart';

mixin _AlarmRebuildOps on _AlarmRepositoryBase {
  /// Rebuilds the rolling window: next 48 h plus next 60 future alarms.
  /// Called on app open, after occurrence rebuilds, and by the daily job.
  Future<int> rebuildWindow({bool dueTomorrowEnabled = true}) async {
    final now = _now();
    final candidates = <AlarmCandidate>[
      ...await _eventCandidates(now),
      ...await _taskCandidates(),
      if (dueTomorrowEnabled) ...await _dueTomorrowCandidates(now),
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
              ..where(
                (c) =>
                    c.startUtc.isBiggerThanValue(now - msPerDay) &
                    c.sourceType.equals('event'),
              )
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
          ? DateTime(y, m, d, 9).toUtc().millisecondsSinceEpoch
          : DateTime(
              y,
              m,
              d,
              mins ~/ 60,
              mins % 60,
            ).toUtc().millisecondsSinceEpoch;
      final title = t.title.isEmpty ? 'Task' : t.title;
      // Custom reminder offsets; default preserves at-time-only behavior.
      final raw = t.reminders;
      final offsets = raw == null || raw.trim().isEmpty
          ? const [0]
          : parseReminderOffsets(raw);
      for (final off in offsets) {
        out.add(
          AlarmCandidate(
            sourceType: 'task_reminder',
            sourceId: '${t.id}#r$off',
            fireAtUtcMs: fire - off * msPerMinute,
            preset: AlarmPreset.notification.id,
            kind: 'reminder',
            title: title,
          ),
        );
      }
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

  Future<List<AlarmCandidate>> _dueTomorrowCandidates(int now) async {
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
      final dueLocal = mins == null
          ? DateTime(y, m, d, 9, 0)
          : DateTime(y, m, d, mins ~/ 60, mins % 60);
      final dueUtcMs = dueLocal.toUtc().millisecondsSinceEpoch;
      final fireLocalRaw = dueLocal.subtract(const Duration(hours: 24));
      final fireLocal = _AlarmRepositoryBase.clampDueTomorrow(fireLocalRaw);
      final fireUtcMs = fireLocal.toUtc().millisecondsSinceEpoch;
      if (fireUtcMs <= now) continue;
      if (fireUtcMs >= dueUtcMs) continue;
      final title = t.title.isEmpty ? 'Task' : t.title;
      out.add(
        AlarmCandidate(
          sourceType: 'task_due_tomorrow',
          sourceId: '${t.id}#tomorrow',
          fireAtUtcMs: fireUtcMs,
          preset: AlarmPreset.notification.id,
          kind: 'reminder',
          title: 'Due tomorrow: $title',
        ),
      );
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
}
