part of '../event_repository.dart';

mixin _EventCreateOps on _EventRepositoryBase {
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
}
