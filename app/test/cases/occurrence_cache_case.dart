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
