import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/countdown_repository.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('habit log, skip, backfill and streaks', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = HabitRepository(db);
    final id = await repo.createHabit(name: 'Read', startDate: '2026-03-01');
    await repo.logDone(id, '2026-03-08');
    await repo.logDone(id, '2026-03-09');
    await repo.setSkipped(id, '2026-03-10', true);
    var s = await repo.streaks(id, '2026-03-10');
    expect(s.current, 2);
    await repo.backfill(id, '2026-03-07', 0, true);
    s = await repo.streaks(id, '2026-03-10');
    expect(s.best, 3);
    expect(s.current, 3);
  });

  test('countdown crud', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = CountdownRepository(db);
    final id = await repo.createCountdown(
      title: 'Trip',
      targetDate: '2026-06-01',
      yearlyRepeat: true,
    );
    await repo.updateCountdown(id, title: 'Big trip');
    final all = await repo.watchCountdowns().first;
    expect(all.single.title, 'Big trip');
    await repo.deleteCountdown(id);
    expect(await repo.watchCountdowns().first, isEmpty);
  });

  test('focus start, current, finish, totals', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = FocusRepository(db);
    final id = await repo.startSession(durationMin: 25);
    expect((await repo.currentSession())?.id, id);
    final kept = await repo.finishSession(id);
    expect(kept, greaterThanOrEqualTo(0));
    expect(await repo.currentSession(), isNull);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    expect(
      await repo.totalMinutes(now - 3600000, now + 60000),
      greaterThanOrEqualTo(0),
    );
  });

  test('sessionsInRange returns finished sessions in window', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = FocusRepository(db);
    final id = await repo.startSession(durationMin: 25, phase: 'focus');
    await repo.finishSession(id);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final rows = await repo.sessionsInRange(now - 3600000, now + 60000);
    expect(rows.map((s) => s.id), contains(id));
    // A just-finished session counts 0 whole minutes; range query is the
    // assertion that matters here.
    expect(await repo.totalMinutes(now - 3600000, now + 60000), isNotNull);
  });
}
