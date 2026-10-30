import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<String> _setup(
  AppDatabase db, {
  String rrule = 'FREQ=DAILY;COUNT=5',
}) async {
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
  final repo = EventRepository(db, OccurrenceRepository(db));
  return repo.createEvent(
    calendarId: 'cal1',
    title: 'Standup',
    startUtc: DateTime.utc(2026, 3, 2, 9),
    endUtc: DateTime.utc(2026, 3, 2, 9, 30),
    tzId: 'UTC',
    rrule: rrule,
  );
}

Future<int> _count(AppDatabase db) async {
  return (await db.select(db.events).get()).length;
}

void main() {
  test('delete single creates cancelled exception', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.deleteOccurrence(
      master,
      DateTime.utc(2026, 3, 3, 9),
      scope: EditScope.single,
    );
    final rows = await db.select(db.events).get();
    expect(rows.length, 2);
    final ex = rows.firstWhere((e) => e.id != master);
    expect(ex.status, 'cancelled');
    expect(
      ex.originalStart,
      DateTime.utc(2026, 3, 3, 9).millisecondsSinceEpoch,
    );
  });

  test('delete following truncates with UNTIL', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.deleteOccurrence(
      master,
      DateTime.utc(2026, 3, 4, 9),
      scope: EditScope.following,
    );
    final m = await (db.select(
      db.events,
    )..where((e) => e.id.equals(master))).getSingle();
    expect(m.rrule, contains('UNTIL=20260304T085959Z'));
    expect(m.rrule, isNot(contains('COUNT')));
  });

  test('delete following on first occurrence deletes all', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.deleteOccurrence(
      master,
      DateTime.utc(2026, 3, 2, 9),
      scope: EditScope.following,
    );
    final rows = await db.select(db.events).get();
    expect(rows.every((e) => e.deletedAt != null), isTrue);
  });

  test('delete all soft-deletes master and exceptions', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.deleteOccurrence(
      master,
      DateTime.utc(2026, 3, 3, 9),
      scope: EditScope.single,
    );
    expect(await _count(db), 2);
    await repo.deleteEvent(master);
    final rows = await db.select(db.events).get();
    expect(rows.every((e) => e.deletedAt != null), isTrue);
  });

  test('edit single creates exception with changed fields', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.editOccurrence(
      master,
      DateTime.utc(2026, 3, 3, 9),
      scope: EditScope.single,
      title: 'Special standup',
    );
    final rows = await db.select(db.events).get();
    expect(rows.length, 2);
    final ex = rows.firstWhere((e) => e.id != master);
    expect(ex.title, 'Special standup');
    expect(ex.recurringMasterId, master);
  });

  test('edit following splits series', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.editOccurrence(
      master,
      DateTime.utc(2026, 3, 4, 9),
      scope: EditScope.following,
      title: 'New title',
      startUtc: DateTime.utc(2026, 3, 4, 10),
      endUtc: DateTime.utc(2026, 3, 4, 10, 30),
    );
    final rows = (await db.select(db.events).get()).where(
      (e) => e.deletedAt == null,
    );
    // Old master truncated + new master from Mar 4.
    expect(rows.length, 2);
    final split = rows.firstWhere((e) => e.id != master);
    expect(split.title, 'New title');
    expect(split.rrule, isNotNull);
    expect(
      DateTime.fromMillisecondsSinceEpoch(split.startUtc!, isUtc: true),
      DateTime.utc(2026, 3, 4, 10),
    );
  });

  test('edit all patches master', () async {
    final db = _db();
    addTearDown(db.close);
    final master = await _setup(db);
    final repo = EventRepository(db, OccurrenceRepository(db));
    await repo.editOccurrence(
      master,
      DateTime.utc(2026, 3, 3, 9),
      scope: EditScope.all,
      title: 'Renamed',
    );
    final m = await (db.select(
      db.events,
    )..where((e) => e.id.equals(master))).getSingle();
    expect(m.title, 'Renamed');
    expect(await _count(db), 1);
  });

  test('rsvp updates attendee and queues sync', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final cal = await repo.createCalendar('C');
    final e = await repo.createEvent(calendarId: cal, title: 'M');
    await repo.setAttendees(e, ['me@example.com']);
    final atts = await repo.attendeesOf(e);
    expect(atts, hasLength(1));
    await repo.setRsvp(atts.first.id, 'accepted');
    final updated = await repo.attendeesOf(e);
    expect(updated.first.rsvp, 'accepted');
    final outbox = await db.select(db.outbox).get();
    expect(outbox, isNotEmpty);
  });
}
