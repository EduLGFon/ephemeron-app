// Calendar color resolution: per-event override wins, calendar color
// (hex or palette id) is inherited, distinct calendars and task lists
// get distinct stable fallbacks instead of one shared primary.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/presentation/google_calendar_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _cal(AppDatabase db, String id, {String? color}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: id,
          name: id,
          color: Value(color),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _event(
  AppDatabase db,
  String id,
  String calId, {
  String? colorId,
  required int startUtc,
  required int endUtc,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: id,
          calendarId: calId,
          title: Value(id),
          startUtc: Value(startUtc),
          endUtc: Value(endUtc),
          colorId: Value(colorId),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _taskList(AppDatabase db, String id, {String? color}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.taskLists)
      .insert(
        TaskListsCompanion.insert(
          id: id,
          name: id,
          color: Value(color),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _task(
  AppDatabase db,
  String id,
  String? listId,
  String dueDate,
) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          listId: Value(listId),
          title: Value(id),
          dueDate: Value(dueDate),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

void main() {
  test('hex and palette ids resolve to distinct colors', () {
    expect(googleCalendarColor('1'), googleCalendarColors['1']);
    expect(tryParseCssHex('#039be5'), const Color(0xFF039BE5));
    expect(tryParseCssHex('not-a-color'), isNull);
    // Empty/unknown falls back instead of throwing.
    expect(googleCalendarColor('', fallback: Colors.red), Colors.red);
  });

  test('stable fallback differs per calendar seed', () {
    final a = stablePaletteIdFor('cal:aaa');
    final b = stablePaletteIdFor('cal:bbb');
    expect(googleCalendarColors.containsKey(a), isTrue);
    expect(googleCalendarColors.containsKey(b), isTrue);
    expect(a, isNot(equals(b)));
    expect(stablePaletteIdFor('cal:aaa'), a);
  });

  test('event inherits calendar hex; per-event override wins', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db, 'work', color: '#039be5');
    await _cal(db, 'home');
    final s = DateTime.utc(2026, 3, 3, 9).millisecondsSinceEpoch;
    final e = DateTime.utc(2026, 3, 3, 10).millisecondsSinceEpoch;
    await _event(db, 'e1', 'work', startUtc: s, endUtc: e);
    await _event(db, 'e2', 'home', startUtc: s, endUtc: e);
    await _event(db, 'e3', 'work', colorId: '9', startUtc: s, endUtc: e);
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 5),
    );
    final rows = await repo.occurrencesForDay('2026-03-03');
    final byId = {for (final r in rows) r.eventId: r};
    expect(byId['e1']!.colorId, '#039be5');
    expect(byId['e2']!.colorId, stablePaletteIdFor('cal:home'));
    expect(byId['e3']!.colorId, '9');
    expect(byId['e1']!.colorId, isNot(equals(byId['e2']!.colorId)));
  });

  test('tasks in different lists get different colors', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db, 'cal1');
    await _taskList(db, 'list-a');
    await _taskList(db, 'list-b');
    await _task(db, 't1', 'list-a', '2026-03-03');
    await _task(db, 't2', 'list-b', '2026-03-03');
    final repo = OccurrenceRepository(db);
    await repo.rebuildWindow(
      windowStartUtc: DateTime.utc(2026, 3, 1),
      windowEndUtc: DateTime.utc(2026, 3, 5),
    );
    final rows = await repo.occurrencesForDay('2026-03-03');
    final byId = {for (final r in rows) r.eventId: r};
    expect(byId['t1']!.colorId, isNotNull);
    expect(byId['t2']!.colorId, isNotNull);
    expect(byId['t1']!.colorId, isNot(equals(byId['t2']!.colorId)));
  });
}
