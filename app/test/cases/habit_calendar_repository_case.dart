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

  test('range stream includes reminder time and goal metadata', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Water',
      frequency: 'daily',
      startDate: '2026-03-01',
      reminderTime: '09:30',
      goalAmount: 5,
      unit: 'glasses',
      increment: 2,
    );

    final entry =
        (await repo.watchCalendarEntries('2026-03-01', '2026-03-01').first)
            .single;
    expect(entry.habitId, id);
    expect(entry.timeMinutes, 570);
    expect(entry.unit, 'glasses');
    expect(entry.goalAmount, 5);
    expect(entry.increment, 2);
    expect(entry.amount, 0);
  });

  test(
    'addAmount increments, preserves skip, and completes the goal',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final id = await repo.createHabit(
        name: 'Water',
        frequency: 'daily',
        startDate: '2026-03-01',
        goalAmount: 5,
        unit: 'glasses',
      );

      await repo.addAmount(id, '2026-03-01', 2);
      var log = await repo.logFor(id, '2026-03-01');
      expect(log?.amount, 2);
      expect(log?.done, isFalse);

      await repo.setSkipped(id, '2026-03-01', true);
      await repo.addAmount(id, '2026-03-01', 3);
      log = await repo.logFor(id, '2026-03-01');
      expect(log?.amount, 5);
      expect(log?.done, isTrue);
      expect(log?.skipped, isTrue);

      final outbox = await db.select(db.outbox).get();
      expect(
        outbox.any(
          (o) =>
              o.entity == 'habit_log:$id' &&
              o.entityId == '$id@2026-03-01' &&
              o.op == 'update',
        ),
        isTrue,
      );
    },
  );

  test('skip and backfill enqueue habit log updates', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      frequency: 'daily',
      startDate: '2026-03-01',
    );

    await repo.setSkipped(id, '2026-03-02', true);
    expect((await repo.logFor(id, '2026-03-02'))?.skipped, isTrue);
    await repo.setSkipped(id, '2026-03-02', false);
    expect((await repo.logFor(id, '2026-03-02'))?.skipped, isFalse);

    await repo.backfill(id, '2026-03-03', 2, true);
    final outbox = await db.select(db.outbox).get();
    expect(
      outbox.any(
        (o) =>
            o.entity == 'habit_log:$id' &&
            o.entityId == '$id@2026-03-03' &&
            o.op == 'update',
      ),
      isTrue,
    );
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
