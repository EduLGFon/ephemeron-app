part of '../event_repository.dart';

extension EventRepositoryEvents on EventRepository {
  Future<String> createEvent({
    required String calendarId,
    required String title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? startDate,
    String? endDate,
    bool allDay = false,
    String? tzId,
    String? rrule,
    String? location,
    String? notes,
    String? colorId,
    bool createMeet = false,
    String? reminders,
    String? alarmPreset,
  }) async {
    final id = newId();
    final now = nowMs();
    final account = await _accountOfCalendar(calendarId);
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            id: id,
            calendarId: calendarId,
            title: Value(title),
            startUtc: Value(startUtc?.toUtc().millisecondsSinceEpoch),
            endUtc: Value(endUtc?.toUtc().millisecondsSinceEpoch),
            startDate: Value(startDate),
            // Internally all-day endDate is exclusive (last day + 1).
            endDate: Value(
              endDate ??
                  (allDay && startDate != null
                      ? _nextDate(startDate)
                      : startDate),
            ),
            isAllDay: Value(allDay),
            tzId: Value(tzId),
            rrule: Value(rrule),
            location: Value(location),
            notes: Value(notes),
            colorId: Value(colorId),
            createMeet: Value(createMeet),
            reminders: Value(reminders),
            alarmPreset: Value(alarmPreset),
            dirty: const Value(true),
            googleAccount: Value(account),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue(id, 'create');
    return id;
  }

  /// Soft-deletes a master and its exceptions in one transaction.
  Future<void> deleteEvent(String masterId) async {
    final now = nowMs();
    await _db.transaction(() async {
      for (final id in [
        masterId,
        for (final ex in await exceptionsOf(masterId)) ex.id,
      ]) {
        await (_db.update(_db.events)..where((e) => e.id.equals(id))).write(
          EventsCompanion(
            deletedAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
      }
    });
    await _enqueue(masterId, 'delete');
    await _occ.invalidateEvent(masterId);
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
}
