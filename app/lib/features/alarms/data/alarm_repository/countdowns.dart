part of '../alarm_repository.dart';

mixin _AlarmCountdownCandidatesOps on _AlarmRepositoryBase {
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
}
