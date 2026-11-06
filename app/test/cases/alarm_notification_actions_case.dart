import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:ephemeron/features/alarms/data/alarm_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

String _tomorrowKey() {
  final t = DateTime.now().toUtc().add(const Duration(days: 1));
  return '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ephemeron/alarms');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('snoozeRequest preserves source metadata', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.alarmsIndex)
        .insert(
          AlarmsIndexCompanion.insert(
            id: 'a1',
            sourceType: 'habit_reminder',
            sourceId: 'h1@2026-01-02',
            fireAtUtc: now + 60000,
            requestCode: const Value(1234),
            state: const Value('scheduled'),
            kind: const Value('reminder'),
            title: const Value('Drink water'),
            preset: const Value('notification'),
          ),
        );
    await AlarmRepository(db).snoozeRequest(1234, minutes: 5);
    final row = await (db.select(
      db.alarmsIndex,
    )..where((a) => a.requestCode.equals(1234))).getSingle();
    expect(row.state, 'scheduled');
    expect(row.sourceType, 'habit_reminder');
    expect(row.sourceId, 'h1@2026-01-02');
    expect(row.title, 'Drink water');
    expect(row.kind, 'reminder');
    expect(row.preset, 'notification');
    expect(row.fireAtUtc, greaterThan(now));
    final schedule = calls.where((c) => c.method == 'schedule').last;
    expect(schedule.arguments['sourceType'], 'habit_reminder');
    expect(schedule.arguments['sourceId'], 'h1@2026-01-02');
    expect(schedule.arguments['title'], 'Drink water');
  });

  test('completing a task cancels pending task alarms', () async {
    final db = _db();
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    final id = await tasks.createTask(
      title: 'Pay bill',
      dueDate: _tomorrowKey(),
      dueTime: 9 * 60,
      reminders: '[30,0]',
      alarmPreset: 'full_short',
    );
    await AlarmRepository(db).rebuildWindow(dueTomorrowEnabled: false);
    final before = await (db.select(
      db.alarmsIndex,
    )..where((a) => a.sourceId.like('%$id%'))).get();
    expect(before, isNotEmpty);
    await tasks.completeTask(id);
    final after =
        await (db.select(db.alarmsIndex)..where(
              (a) => a.sourceId.like('%$id%') & a.state.equals('scheduled'),
            ))
            .get();
    expect(after, isEmpty);
  });

  test(
    'marking habit done cancels that day alarms so snoozed alarm does not recur',
    () async {
      final db = _db();
      addTearDown(db.close);
      final habits = HabitRepository(db);
      final habitId = await habits.createHabit(
        name: 'Stretch',
        frequency: 'daily',
      );
      final day = habitDateKey(DateTime.now());
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      // Simulate a snoozed alarm for today that would fire again.
      await db
          .into(db.alarmsIndex)
          .insert(
            AlarmsIndexCompanion.insert(
              id: 'snoozed1',
              sourceType: 'habit_reminder',
              sourceId: '$habitId@$day',
              fireAtUtc: now + 10 * 60 * 1000,
              requestCode: const Value(4242),
              state: const Value('scheduled'),
              kind: const Value('reminder'),
              title: const Value('Stretch'),
              preset: const Value('notification'),
            ),
          );
      await habits.setDone(habitId, day, true);
      final row = await (db.select(
        db.alarmsIndex,
      )..where((a) => a.id.equals('snoozed1'))).getSingle();
      expect(row.state, isNot('scheduled'));
    },
  );

  test('cancelForHabitDay keeps other days scheduled', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.alarmsIndex)
        .insert(
          AlarmsIndexCompanion.insert(
            id: 'd1',
            sourceType: 'habit_reminder',
            sourceId: 'h9@2026-01-02',
            fireAtUtc: now + 60000,
            requestCode: const Value(1),
            state: const Value('scheduled'),
          ),
        );
    await db
        .into(db.alarmsIndex)
        .insert(
          AlarmsIndexCompanion.insert(
            id: 'd2',
            sourceType: 'habit_reminder',
            sourceId: 'h9@2026-01-03',
            fireAtUtc: now + 120000,
            requestCode: const Value(2),
            state: const Value('scheduled'),
          ),
        );
    await AlarmRepository(db).cancelForHabitDay('h9', '2026-01-02');
    final a = await (db.select(
      db.alarmsIndex,
    )..where((r) => r.id.equals('d1'))).getSingleOrNull();
    final b = await (db.select(
      db.alarmsIndex,
    )..where((r) => r.id.equals('d2'))).getSingle();
    expect(a, isNull);
    expect(b.state, 'scheduled');
  });

  test('numeric habit addAmount reaching goal cancels day alarms', () async {
    final db = _db();
    addTearDown(db.close);
    final habits = HabitRepository(db);
    final habitId = await habits.createHabit(
      name: 'Water',
      frequency: 'daily',
      goalAmount: 8,
      increment: 1,
      unit: 'glasses',
    );
    final day = habitDateKey(DateTime.now());
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.alarmsIndex)
        .insert(
          AlarmsIndexCompanion.insert(
            id: 'hw1',
            sourceType: 'habit',
            sourceId: '$habitId@$day',
            fireAtUtc: now + 60000,
            requestCode: const Value(777),
            state: const Value('scheduled'),
            kind: const Value('alarm'),
            preset: const Value('full_short'),
          ),
        );
    await habits.addAmount(habitId, day, 8);
    final row = await (db.select(
      db.alarmsIndex,
    )..where((r) => r.id.equals('hw1'))).getSingle();
    expect(row.state, isNot('scheduled'));
  });
}
