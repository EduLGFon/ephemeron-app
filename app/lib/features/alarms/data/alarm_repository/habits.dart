part of '../alarm_repository.dart';

mixin _AlarmHabitCandidatesOps on _AlarmRepositoryBase {
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
