import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<String> _eventWithAttendees(
  AppDatabase db, {
  required List<({String email, String? rsvp, bool self, bool org})> rows,
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
  final id = await repo.createEvent(
    calendarId: 'cal1',
    title: 'Invite',
    startUtc: DateTime.utc(2026, 3, 2, 9),
    endUtc: DateTime.utc(2026, 3, 2, 10),
    tzId: 'UTC',
  );
  for (final r in rows) {
    await db
        .into(db.eventAttendees)
        .insert(
          EventAttendeesCompanion.insert(
            id: '${id}_${r.email}',
            eventId: id,
            email: r.email,
            rsvp: Value(r.rsvp),
            isSelf: Value(r.self),
            isOrganizer: Value(r.org),
          ),
        );
  }
  return id;
}

void main() {
  test('flagged isSelf row wins over email match', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(
      db,
      rows: [
        (email: 'me@x.com', rsvp: 'tentative', self: true, org: false),
        (email: 'other@x.com', rsvp: 'accepted', self: false, org: false),
      ],
    );
    final self = await repo.selfAttendeeOf(id, ['other@x.com']);
    expect(self?.email, 'me@x.com');
  });

  test('email match resolves self when flag missing', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(
      db,
      rows: [
        (email: 'boss@x.com', rsvp: null, self: false, org: true),
        (email: 'me@x.com', rsvp: 'accepted', self: false, org: false),
      ],
    );
    final self = await repo.selfAttendeeOf(id, ['me@x.com']);
    expect(self?.email, 'me@x.com');
    expect(self?.rsvp, 'accepted');
  });

  test('known accounts without match resolve to null', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(
      db,
      rows: [
        (email: 'stranger@x.com', rsvp: 'accepted', self: false, org: false),
      ],
    );
    expect(await repo.selfAttendeeOf(id, ['me@x.com']), isNull);
  });

  test('no attendees resolve to null', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(db, rows: []);
    expect(await repo.selfAttendeeOf(id, ['me@x.com']), isNull);
    expect(await repo.selfAttendeeOf(id, []), isNull);
  });

  test('signed out falls back to first guest', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(
      db,
      rows: [
        (email: 'boss@x.com', rsvp: null, self: false, org: true),
        (email: 'guest@x.com', rsvp: null, self: false, org: false),
      ],
    );
    final self = await repo.selfAttendeeOf(id, []);
    expect(self?.email, 'guest@x.com');
  });

  test('setRsvp heals missing isSelf flag', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = EventRepository(db, OccurrenceRepository(db));
    final id = await _eventWithAttendees(
      db,
      rows: [(email: 'me@x.com', rsvp: null, self: false, org: false)],
    );
    final row = (await repo.attendeesOf(id)).single;
    await repo.setRsvp(row.id, 'accepted');
    final after = await repo.selfAttendeeOf(id, ['me@x.com']);
    expect(after?.rsvp, 'accepted');
    expect(after?.isSelf, isTrue);
  });
}
