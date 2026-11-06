part of '../habit_repository.dart';

mixin _HabitCalendarOps on _HabitRepositoryBase {
  /// Reactive stream of scheduled habit entries with their log state for a
  /// date-key range (inclusive). One Drift query; reads habits + habitLogs.
  Stream<List<HabitCalendarEntry>> watchCalendarEntries(
    String fromKey,
    String toKey,
  ) {
    final query = _db.customSelect(
      'WITH RECURSIVE days(d) AS ('
      "SELECT ?1 UNION ALL SELECT date(d, '+1 day') FROM days WHERE d < ?2"
      ') '
      'SELECT h.id AS habit_id, h.name AS habit_name, '
      'h.frequency AS frequency, h.weekdays_mask AS weekdays_mask, '
      'h.weekly_target AS weekly_target, h.interval_days AS interval_days, '
      'h.start_date AS start_date, h.reminder_time AS reminder_time, '
      'h.unit AS unit, h.goal_amount AS goal_amount, '
      'h.increment AS increment, '
      'l.amount AS log_amount, l.done AS log_done, '
      'l.skipped AS log_skipped, days.d AS day '
      'FROM days CROSS JOIN habits h '
      'LEFT JOIN habit_logs l ON l.habit_id = h.id AND l.day_key = days.d '
      "WHERE h.archived = 0 AND h.deleted_at IS NULL "
      "AND h.id NOT IN (SELECT entity_id FROM outbox WHERE entity = 'habit' AND op = 'delete') "
      "AND h.id NOT IN (SELECT entity_id FROM outbox WHERE entity = 'habit' AND op = 'archive') "
      "AND h.id NOT IN (SELECT entity_id FROM outbox WHERE entity = 'habit' AND op = 'unarchive')",
      variables: [Variable<String>(fromKey), Variable<String>(toKey)],
      readsFrom: {_db.habits, _db.habitLogs, _db.outbox},
    );
    return query.watch().map((rows) {
      final out = <HabitCalendarEntry>[];
      for (final r in rows) {
        final day = r.read<String>('day');
        final spec = HabitSpec(
          frequency: r.read<String>('frequency'),
          weekdaysMask: r.read<int>('weekdays_mask'),
          weeklyTarget: r.readNullable<int>('weekly_target') ?? 0,
          intervalDays: r.readNullable<int>('interval_days') ?? 0,
          startDate: r.readNullable<String>('start_date'),
        );
        if (!isHabitScheduled(spec, parseKey(day))) continue;
        out.add(
          HabitCalendarEntry(
            habitId: r.read<String>('habit_id'),
            habitName: r.read<String>('habit_name'),
            dayKey: day,
            timeMinutes: parseHabitTimeMinutes(
              r.readNullable<String>('reminder_time'),
            ),
            unit: r.readNullable<String>('unit'),
            goalAmount: r.readNullable<double>('goal_amount'),
            increment: r.readNullable<double>('increment'),
            amount: r.readNullable<double>('log_amount') ?? 0,
            done: (r.readNullable<int>('log_done') ?? 0) == 1,
            skipped: (r.readNullable<int>('log_skipped') ?? 0) == 1,
          ),
        );
      }
      out.sort((a, b) {
        final c = a.dayKey.compareTo(b.dayKey);
        if (c != 0) return c;
        return a.habitName.compareTo(b.habitName);
      });
      return out;
    });
  }
}
