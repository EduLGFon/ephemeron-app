part of '../alarm_repository.dart';

mixin _AlarmRebuildOps
    on
        _AlarmRepositoryBase,
        _AlarmEventCandidatesOps,
        _AlarmTaskCandidatesOps,
        _AlarmCountdownCandidatesOps,
        _AlarmHabitCandidatesOps {
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
}
