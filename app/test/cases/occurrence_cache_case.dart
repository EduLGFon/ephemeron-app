import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _cal(AppDatabase db) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: 'cal1',
          name: 'c',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _event(
  AppDatabase db, {
  required String id,
  String? rrule,
  String? masterId,
  int? originalStart,
  String status = 'confirmed',
  int? startUtc,
  int? endUtc,
  String? tzId,
  String? startDate,
  String? endDate,
  bool isAllDay = false,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: id,
          calendarId: 'cal1',
          createdAt: now,
          updatedAt: now,
          startUtc: Value(startUtc),
          endUtc: Value(endUtc),
          startDate: Value(startDate),
          endDate: Value(endDate),
          isAllDay: Value(isAllDay),
          rrule: Value(rrule),
          recurringMasterId: Value(masterId),
          originalStart: Value(originalStart),
          status: Value(status),
          tzId: Value(tzId),
        ),
      );
}

void main() {
  test('rebuild expands a daily master into the window only', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final start = DateTime.utc(2026, 3, 2, 9);
    await _event(
      db,
      id: 'm1',
      rrule: 'FREQ=DAILY;COUNT=10',
      startUtc: start.millisecondsSinceEpoch,
      endUtc: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      tzId: 'UTC',
    );
    final repo = OccurrenceRepository(db);
    final n = await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 5, 23, 59),
    );
    expect(n, 4);
    final rows = await repo.occurrencesForDay('2026-03-03');
    expect(rows.length, 1);
    expect(rows.single.eventId, 'm1');
  });

  test('cancelled exception removes that occurrence', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final start = DateTime.utc(2026, 3, 2, 9);
    await _event(
      db,
      id: 'm1',
      rrule: 'FREQ=DAILY;COUNT=5',
      startUtc: start.millisecondsSinceEpoch,
      endUtc: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      tzId: 'UTC',
    );
    await _event(
      db,
      id: 'ex1',
      masterId: 'm1',
      originalStart: DateTime.utc(2026, 3, 3, 9).millisecondsSinceEpoch,
      status: 'cancelled',
    );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 8),
    );
    expect(await repo.occurrencesForDay('2026-03-03'), isEmpty);
    expect((await repo.occurrencesForDay('2026-03-04')).length, 1);
  });

  test('all-day exclusive end spans only the covered days', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    await _event(
      db,
      id: 'single',
      startDate: '2026-11-03',
      endDate: '2026-11-04',
      isAllDay: true,
    );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 11, 1),
      windowEndUtc: DateTime.utc(2026, 11, 30),
    );
    expect((await repo.occurrencesForDay('2026-11-03')).length, 1);
    expect(await repo.occurrencesForDay('2026-11-04'), isEmpty);
  });

  test('all-day multi-day exclusive end excludes the end date', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    await _event(
      db,
      id: 'multi',
      startDate: '2026-11-03',
      endDate: '2026-11-06',
      isAllDay: true,
    );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 11, 1),
      windowEndUtc: DateTime.utc(2026, 11, 30),
    );
    for (final day in ['2026-11-03', '2026-11-04', '2026-11-05']) {
      expect((await repo.occurrencesForDay(day)).length, 1);
    }
    expect(await repo.occurrencesForDay('2026-11-06'), isEmpty);
  });

  test('legacy all-day row with end==start stays one day', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    await _event(
      db,
      id: 'legacy',
      startDate: '2026-11-03',
      endDate: '2026-11-03',
      isAllDay: true,
    );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 11, 1),
      windowEndUtc: DateTime.utc(2026, 11, 30),
    );
    expect((await repo.occurrencesForDay('2026-11-03')).length, 1);
    expect(await repo.occurrencesForDay('2026-11-04'), isEmpty);
  });

  test('task occurrences use planned date as all-day when set', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 't1',
            title: const Value('Plan'),
            dueDate: const Value('2026-03-10'),
            plannedDate: const Value('2026-03-05'),
            dueTime: const Value(540),
            durationMin: const Value(60),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 31),
    );
    final rows = await repo.occurrencesForDay('2026-03-05');
    expect(rows, hasLength(1));
    expect(rows.single.eventId, 't1');
    expect(
      rows.single.startUtc,
      DateTime(2026, 3, 5).toUtc().millisecondsSinceEpoch,
    );
    expect(await repo.occurrencesForDay('2026-03-10'), isEmpty);
  });

  test('task occurrences fall back to timed due date when unplanned', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 't2',
            title: const Value('Due only'),
            dueDate: const Value('2026-03-06'),
            dueTime: const Value(540),
            durationMin: const Value(60),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 31),
    );
    final rows = await repo.occurrencesForDay('2026-03-06');
    expect(rows, hasLength(1));
    expect(
      rows.single.startUtc,
      DateTime(2026, 3, 6, 9).toUtc().millisecondsSinceEpoch,
    );
    expect(
      rows.single.endUtc,
      DateTime(2026, 3, 6, 10).toUtc().millisecondsSinceEpoch,
    );
  });

  test('invalidateEvent clears rows for master and exceptions', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final start = DateTime.utc(2026, 3, 2, 9);
    await _event(
      db,
      id: 'm1',
      rrule: 'FREQ=DAILY;COUNT=5',
      startUtc: start.millisecondsSinceEpoch,
      endUtc: start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      tzId: 'UTC',
    );
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 8),
    );
    await repo.invalidateEvent('m1');
    expect(await repo.occurrencesForDay('2026-03-04'), isEmpty);
  });
}
