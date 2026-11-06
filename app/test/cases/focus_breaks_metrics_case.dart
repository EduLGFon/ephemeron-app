import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/focus_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test(
    'qualifying focus excludes breaks and sessions shorter than 5 minutes',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = FocusRepository(db);
      final base = DateTime.utc(2026, 1, 2, 10).millisecondsSinceEpoch;
      const min = 60000;

      Future<void> insert(String id, String phase, int start, int end) {
        return db
            .into(db.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: id,
                startUtc: start,
                endUtc: Value(end),
                phase: Value(phase),
                createdAt: start,
                updatedAt: end,
              ),
            );
      }

      await insert('focus-long', 'focus', base, base + 25 * min);
      await insert('focus-short', 'focus', base + 30 * min, base + 34 * min);
      await insert('focus-boundary', 'focus', base + 40 * min, base + 45 * min);
      await insert('break-long', 'break', base + 50 * min, base + 60 * min);
      await insert('break-short', 'break', base + 70 * min, base + 72 * min);
      await insert(
        'stopwatch-long',
        'stopwatch',
        base + 80 * min,
        base + 90 * min,
      );
      await insert(
        'stopwatch-short',
        'stopwatch',
        base + 95 * min,
        base + 97 * min,
      );

      final from = base - min;
      final to = base + 120 * min;
      expect(await repo.totalFocusMinutes(from, to), 25 + 5 + 10);
      expect(await repo.totalBreakMinutes(from, to), 10 + 2);
    },
  );

  test('running focus session under 5 minutes does not count yet', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = FocusRepository(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const min = 60000;
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: 'running',
            startUtc: now - 3 * min,
            phase: const Value('focus'),
            createdAt: now - 3 * min,
            updatedAt: now,
          ),
        );
    expect(await repo.totalFocusMinutes(now - 60 * min, now), 0);
  });

  test('running break session counts as break time', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = FocusRepository(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const min = 60000;
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: 'running-break',
            startUtc: now - 3 * min,
            phase: const Value('break'),
            createdAt: now - 3 * min,
            updatedAt: now,
          ),
        );
    expect(
      await repo.totalBreakMinutes(now - 60 * min, now),
      greaterThanOrEqualTo(2),
    );
  });

  test('session qualification helpers treat stopwatch as focus work', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    const min = 60000;
    final s = FocusSession(
      id: 's',
      taskId: null,
      habitId: null,
      startUtc: now - 10 * min,
      endUtc: now,
      targetEndUtc: null,
      phase: 'stopwatch',
      note: null,
      alarmPreset: null,
      createdAt: now,
      updatedAt: now,
    );
    expect(FocusRepository.isBreakSession(s), isFalse);
    expect(FocusRepository.isQualifyingFocusSession(s, atUtc: now), isTrue);
  });
}
