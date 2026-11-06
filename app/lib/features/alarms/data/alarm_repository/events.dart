part of '../alarm_repository.dart';

mixin _AlarmEventCandidatesOps on _AlarmRepositoryBase {
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
}
