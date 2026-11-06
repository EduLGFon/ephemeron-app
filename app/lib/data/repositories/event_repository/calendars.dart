part of '../event_repository.dart';

mixin _EventCalendarOps on _EventRepositoryBase {
  Stream<List<Calendar>> watchCalendars() {
    return (_db.select(
      _db.calendars,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();
  }

  Future<void> setAttendees(String eventId, List<String> emails) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.eventAttendees,
      )..where((a) => a.eventId.equals(eventId))).go();
      for (final email in emails) {
        final trimmed = email.trim();
        if (trimmed.isEmpty) continue;
        await _db
            .into(_db.eventAttendees)
            .insert(
              EventAttendeesCompanion.insert(
                id: newId(),
                eventId: eventId,
                email: trimmed,
              ),
            );
      }
    });
  }

  Future<List<EventAttendee>> attendeesOf(String eventId) {
    return (_db.select(
      _db.eventAttendees,
    )..where((a) => a.eventId.equals(eventId))).get();
  }

  Future<EventAttendee?> selfAttendeeOf(
    String eventId,
    List<String> accountEmails,
  ) async {
    return resolveSelf(await attendeesOf(eventId), accountEmails);
  }

  static EventAttendee? resolveSelf(
    List<EventAttendee> atts,
    List<String> accountEmails,
  ) {
    if (atts.isEmpty) return null;
    final flagged = atts.where((a) => a.isSelf).firstOrNull;
    if (flagged != null) return flagged;
    if (accountEmails.isNotEmpty) {
      final known = {for (final e in accountEmails) e.toLowerCase()};
      return atts
          .where((a) => known.contains(a.email.toLowerCase()))
          .firstOrNull;
    }
    final guest = atts.where((a) => !a.isOrganizer).firstOrNull;
    return guest ?? atts.first;
  }

  Future<void> setRsvp(String attendeeId, String rsvp) async {
    assert(
      rsvp == 'accepted' || rsvp == 'tentative' || rsvp == 'declined',
      'invalid rsvp',
    );
    String? eventId;
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.eventAttendees,
      )..where((a) => a.id.equals(attendeeId))).getSingleOrNull();
      if (row == null) return;
      eventId = row.eventId;
      await (_db.update(
        _db.eventAttendees,
      )..where((a) => a.id.equals(attendeeId))).write(
        EventAttendeesCompanion(rsvp: Value(rsvp), isSelf: const Value(true)),
      );
      await (_db.update(
        _db.events,
      )..where((e) => e.id.equals(row.eventId))).write(
        EventsCompanion(updatedAt: Value(nowMs()), dirty: const Value(true)),
      );
    });
    if (eventId != null) await _enqueue(eventId!, 'update');
  }

  Future<String> createCalendar(
    String name, {
    String source = 'device',
    String? color,
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.calendars)
        .insert(
          CalendarsCompanion.insert(
            id: id,
            name: name,
            source: Value(source),
            color: Value(color),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> setNotesOverflow(String eventId, String? noteId) async {
    await (_db.update(_db.events)..where((e) => e.id.equals(eventId))).write(
      EventsCompanion(
        notesOverflowNoteId: Value(noteId),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
  }

  Future<List<Event>> overlappingEvents({
    required String calendarId,
    required DateTime startUtc,
    required DateTime endUtc,
    String? excludeId,
  }) async {
    final rows =
        await (dbSelect()..where(
              (e) => e.calendarId.equals(calendarId) & e.deletedAt.isNull(),
            ))
            .get();
    final s = startUtc.toUtc().millisecondsSinceEpoch;
    final e = endUtc.toUtc().millisecondsSinceEpoch;
    return rows.where((ev) {
      if (excludeId != null && ev.id == excludeId) return false;
      final es = ev.startUtc;
      final ee = ev.endUtc ?? ev.startUtc;
      if (es == null || ee == null) return false;
      return es < e && s < ee;
    }).toList();
  }

  Future<void> setCalendarEnabled(String id, bool enabled) async {
    await (_db.update(_db.calendars)..where((c) => c.id.equals(id))).write(
      CalendarsCompanion(enabled: Value(enabled), updatedAt: Value(nowMs())),
    );
  }

  Stream<List<Event>> watchExceptions(String masterId) {
    return (dbSelect()..where((e) => e.recurringMasterId.equals(masterId)))
        .watch();
  }
}
