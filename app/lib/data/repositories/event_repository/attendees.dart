part of '../event_repository.dart';

extension EventRepositoryAttendees on EventRepository {
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

  /// Resolves the signed-in user's own attendee row for RSVP display.
  /// Prefers the synced `isSelf` flag, then matches attendee email against
  /// [accountEmails]. When no account identity is known (signed out or not
  /// restored yet), falls back to the first non-organizer row so local-only
  /// invites keep a respond target. Returns null when the event has no
  /// attendees or the signed-in user is not among them.
  Future<EventAttendee?> selfAttendeeOf(
    String eventId,
    List<String> accountEmails,
  ) async {
    return EventRepository.resolveSelf(await attendeesOf(eventId), accountEmails);
  }

  /// Sets the RSVP status of one attendee row and queues a sync update.
  /// Accepted values: accepted, tentative, declined.
  /// Also marks the row as self: the chips only ever target the resolved
  /// self row, so responding heals rows imported before self flags existed.
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
}
