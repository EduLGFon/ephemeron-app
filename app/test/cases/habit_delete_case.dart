import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test(
    'deleteHabit hides habit from watchHabits and enqueues outbox op',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final id = await repo.createHabit(
        name: 'Read',
        frequency: 'daily',
        startDate: '2026-03-01',
      );
      await repo.deleteHabit(id);
      final habits = await repo.watchHabits().first;
      expect(habits, isEmpty);
      final outbox = await db.select(db.outbox).get();
      expect(
        outbox.any(
          (o) => o.entity == 'habit' && o.entityId == id && o.op == 'delete',
        ),
        isTrue,
      );
      final row = await (db.select(
        db.habits,
      )..where((h) => h.id.equals(id))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.dirty, isTrue);
    },
  );

  test('restoreHabit clears deletedAt and reappears in watchHabits', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      frequency: 'daily',
      startDate: '2026-03-01',
    );
    await repo.deleteHabit(id);
    expect(await repo.watchHabits().first, isEmpty);
    await repo.restoreHabit(id);
    final habits = await repo.watchHabits().first;
    expect(habits.map((h) => h.id), contains(id));
    final row = await (db.select(
      db.habits,
    )..where((h) => h.id.equals(id))).getSingle();
    expect(row.deletedAt, isNull);
    expect(row.dirty, isTrue);
    final outbox = await db.select(db.outbox).get();
    expect(
      outbox.any(
        (o) => o.entity == 'habit' && o.entityId == id && o.op == 'update',
      ),
      isTrue,
    );
  });

  test('calendar entries exclude deleted habits', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(
      name: 'Read',
      frequency: 'daily',
      startDate: '2026-03-01',
    );
    await repo.deleteHabit(id);
    final entries = await repo
        .watchCalendarEntries('2026-03-01', '2026-03-03')
        .first;
    expect(entries, isEmpty);
  });

  test(
    'calendar entries exclude habits with pending delete outbox row',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final id = await repo.createHabit(
        name: 'Read',
        frequency: 'daily',
        startDate: '2026-03-01',
      );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'pending-delete',
              entity: 'habit',
              entityId: id,
              op: 'delete',
              createdAt: 0,
            ),
          );
      final entries = await repo
          .watchCalendarEntries('2026-03-01', '2026-03-03')
          .first;
      expect(entries, isEmpty);
    },
  );

  test(
    'calendar entries exclude habits with pending archive outbox row',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = HabitRepository(db);
      final id = await repo.createHabit(
        name: 'Read',
        frequency: 'daily',
        startDate: '2026-03-01',
      );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'pending-archive',
              entity: 'habit',
              entityId: id,
              op: 'archive',
              createdAt: 0,
            ),
          );
      final entries = await repo
          .watchCalendarEntries('2026-03-01', '2026-03-03')
          .first;
      expect(entries, isEmpty);
    },
  );
}
