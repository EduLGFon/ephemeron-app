part of '../alarm_repository.dart';

mixin _AlarmTaskCandidatesOps on _AlarmRepositoryBase {
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
}
