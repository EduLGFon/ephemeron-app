import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
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
  // Tests run with TargetPlatform.android, so AlarmScheduler reaches the
  // MethodChannel: stub it instead of touching the OS.
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ephemeron/alarms');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('task custom offsets schedule one reminder each', () async {
    final db = _db();
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    final id = await tasks.createTask(
      title: 'Dentist',
      dueDate: _tomorrowKey(),
      dueTime: 12 * 60,
      reminders: '[30,0]',
      alarmPreset: 'full_short',
    );
    final n = await AlarmRepository(db).rebuildWindow();
    expect(n, greaterThanOrEqualTo(3));
    final rows = await (db.select(
      db.alarmsIndex,
    )..where((a) => a.sourceId.like('%$id%'))).get();
    final reminders = rows.where((r) => r.kind == 'reminder').toList();
    final alarms = rows.where((r) => r.kind == 'alarm').toList();
    expect(reminders.map((r) => r.sourceId), contains('$id#r30'));
    expect(reminders.map((r) => r.sourceId), contains('$id#r0'));
    expect(alarms.single.sourceId, id);
    expect(alarms.single.preset, 'full_short');
    // Reminder fires precede the alarm fire.
    final alarmFire = alarms.single.fireAtUtc;
    for (final r in reminders) {
      expect(r.fireAtUtc, lessThanOrEqualTo(alarmFire));
    }
  });

  test('task without reminders keeps at-time-only default', () async {
    final db = _db();
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    final id = await tasks.createTask(
      title: 'Call',
      dueDate: _tomorrowKey(),
      dueTime: 9 * 60,
    );
    await AlarmRepository(db).rebuildWindow();
    final rows = await (db.select(
      db.alarmsIndex,
    )..where((a) => a.sourceId.like('%$id%'))).get();
    expect(rows.where((r) => r.kind == 'reminder'), hasLength(1));
    expect(rows.where((r) => r.kind == 'alarm'), isEmpty);
  });

  test('due-tomorrow candidates clamp to 09-17', () async {
    final db = _db();
    addTearDown(db.close);
    final tasks = TaskRepository(db);
    final dayAfter = () {
      final t = DateTime.now().toUtc().add(const Duration(days: 2));
      return '${t.year.toString().padLeft(4, '0')}-'
          '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')}';
    }();
    await tasks.createTask(title: 'Early', dueDate: dayAfter, dueTime: 8 * 60);
    await tasks.createTask(title: 'Noon', dueDate: dayAfter, dueTime: 12 * 60);
    await tasks.createTask(title: 'Late', dueDate: dayAfter, dueTime: 23 * 60);
    await tasks.createTask(title: 'None', dueDate: dayAfter);
    await AlarmRepository(db).rebuildWindow();
    final rows = await (db.select(
      db.alarmsIndex,
    )..where((a) => a.sourceType.equals('task_due_tomorrow'))).get();
    expect(rows, hasLength(4));
    final hours = rows
        .map(
          (r) => DateTime.fromMillisecondsSinceEpoch(
            r.fireAtUtc,
            isUtc: true,
          ).toLocal().hour,
        )
        .toSet();
    expect(hours, containsAll([9, 12, 17]));
  });

  test(
    'rebuildWindow dueTomorrowEnabled false adds no task_due_tomorrow',
    () async {
      final db = _db();
      addTearDown(db.close);
      final tasks = TaskRepository(db);
      await tasks.createTask(
        title: 'Tomorrow',
        dueDate: _tomorrowKey(),
        dueTime: 12 * 60,
      );
      await AlarmRepository(db).rebuildWindow(dueTomorrowEnabled: false);
      final rows = await (db.select(
        db.alarmsIndex,
      )..where((a) => a.sourceType.equals('task_due_tomorrow'))).get();
      expect(rows, isEmpty);
    },
  );

  test('task occurrence-cache rows do not produce event candidates', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.occurrenceCache)
        .insert(
          OccurrenceCacheCompanion.insert(
            id: 'oc1',
            eventId: 't1',
            startUtc: now + 3600000,
            endUtc: now + 7200000,
            dayKey: _tomorrowKey(),
            sourceType: const Value('task'),
          ),
        );
    await AlarmRepository(db).rebuildWindow();
    final rows =
        await (db.select(db.alarmsIndex)..where(
              (a) =>
                  a.sourceType.equals('event_reminder') |
                  a.sourceType.equals('event'),
            ))
            .get();
    expect(rows, isEmpty);
  });
}
