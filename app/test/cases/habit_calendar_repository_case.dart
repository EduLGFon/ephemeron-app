import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test(
    'range stream returns scheduled entries with done/skipped state',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final id = await repo.createHabit(
        name: 'Read',
        frequency: 'daily',
        startDate: '2026-03-01',
      );

      var entries = await repo
          .watchCalendarEntries('2026-03-01', '2026-03-03')
          .first;
      expect(entries, hasLength(3));
      expect(entries.every((e) => e.habitId == id), isTrue);
      expect(entries.every((e) => !e.done && !e.skipped), isTrue);

      await repo.logDone(id, '2026-03-02');
      entries = await repo
          .watchCalendarEntries('2026-03-01', '2026-03-03')
          .first;
      final done = entries.firstWhere((e) => e.dayKey == '2026-03-02');
      expect(done.done, isTrue);
      expect(done.skipped, isFalse);

      await repo.setSkipped(id, '2026-03-03', true);
      entries = await repo
          .watchCalendarEntries('2026-03-01', '2026-03-03')
          .first;
      final skipped = entries.firstWhere((e) => e.dayKey == '2026-03-03');
      expect(skipped.skipped, isTrue);
    },
  );

  test('range stream respects schedule and excludes archived habits', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final weekdays = await repo.createHabit(
      name: 'Gym',
      frequency: 'weekdays',
      weekdaysMask: 31,
      startDate: '2026-03-02',
    );
    final archived = await repo.createHabit(
      name: 'Old',
      frequency: 'daily',
      startDate: '2026-03-01',
    );
    await repo.archiveHabit(archived, true);

    final entries = await repo
        .watchCalendarEntries('2026-03-02', '2026-03-08')
        .first;
    expect(entries.every((e) => e.habitId == weekdays), isTrue);
    expect(entries.map((e) => e.dayKey), [
      '2026-03-02',
      '2026-03-03',
      '2026-03-04',
      '2026-03-05',
      '2026-03-06',
    ]);
  });

  test('toggleHabitDone flips the log state', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      frequency: 'daily',
      startDate: '2026-03-01',
    );

    await repo.toggleHabitDone(id, '2026-03-02');
    expect((await repo.logFor(id, '2026-03-02'))?.done, isTrue);
    await repo.toggleHabitDone(id, '2026-03-02');
    expect((await repo.logFor(id, '2026-03-02'))?.done, isFalse);
  });
}
