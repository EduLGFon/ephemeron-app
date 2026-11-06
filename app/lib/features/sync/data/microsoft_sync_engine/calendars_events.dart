part of '../microsoft_sync_engine.dart';

extension on MicrosoftSyncEngine {
  Future<({int count, Map<String, String> idsByRemote})> _syncCalendars(
    List<MsCalendar> calendars,
    int now,
  ) async {
    final calendarIdByRemote = <String, String>{};
    var calendarCount = 0;
    for (final c in calendars) {
      final remoteId = c.id;
      if (remoteId.isEmpty) continue;
      final existing =
          await (_db.select(_db.calendars)..where(
                (t) =>
                    t.source.equals('microsoft') &
                    t.microsoftAccount.equals(account) &
                    t.remoteId.equals(remoteId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        final id = 'mscal_${account}_$remoteId';
        await _db
            .into(_db.calendars)
            .insert(
              CalendarsCompanion.insert(
                id: id,
                remoteId: Value(remoteId),
                name: c.name.isEmpty ? remoteId : c.name,
                color: Value(c.hexColor),
                source: const Value('microsoft'),
                microsoftAccount: Value(account),
                readOnly: Value(!c.canEdit),
                enabled: const Value(true),
                createdAt: now,
                updatedAt: now,
              ),
            );
        calendarIdByRemote[remoteId] = id;
        calendarCount++;
      } else {
        await (_db.update(
          _db.calendars,
        )..where((t) => t.id.equals(existing.id))).write(
          CalendarsCompanion(
            name: Value(c.name.isEmpty ? existing.name : c.name),
            color: Value(c.hexColor ?? existing.color),
            readOnly: Value(!c.canEdit),
            microsoftAccount: Value(account),
            dirty: const Value(false),
            updatedAt: Value(now),
          ),
        );
        calendarIdByRemote[remoteId] = existing.id;
      }
    }
    return (count: calendarCount, idsByRemote: calendarIdByRemote);
  }

  Future<int> _syncEvents(
    List<MsCalendar> calendars,
    Map<String, String> calendarIdByRemote,
  ) async {
    var eventCount = 0;
    for (final cal in calendars) {
      final localCalId = calendarIdByRemote[cal.id];
      if (localCalId == null) continue;
      final events = await _client.calendarView(
        _windowStart,
        _windowEnd,
        calendarId: cal.id,
      );
      for (final e in events) {
        final remoteId = e.id;
        if (remoteId.isEmpty) continue;
        final existing =
            await (_db.select(_db.events)..where(
                  (t) =>
                      t.microsoftAccount.equals(account) &
                      t.remoteId.equals(remoteId),
                ))
                .getSingleOrNull();
        final isAllDay = e.isAllDay;
        final startUtc = e.start?.utc;
        final endUtc = e.end?.utc;
        final startDate = isAllDay && startUtc != null
            ? _dateStr(startUtc)
            : null;
        final endDate = isAllDay && endUtc != null ? _dateStr(endUtc) : null;
        final title = e.subject ?? '';
        final cancelled = e.isCancelled;
        final status = cancelled ? 'cancelled' : 'confirmed';
        final meetUrl = e.onlineMeetingUrl;
        final location = e.location?.displayName;
        final notes = e.bodyPreview;
        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        if (existing == null) {
          await _db
              .into(_db.events)
              .insert(
                EventsCompanion.insert(
                  id: 'msevt_${account}_$remoteId',
                  calendarId: localCalId,
                  title: Value(title),
                  notes: Value(notes),
                  location: Value(location),
                  startUtc: Value(
                    isAllDay ? null : startUtc?.millisecondsSinceEpoch,
                  ),
                  endUtc: Value(
                    isAllDay ? null : endUtc?.millisecondsSinceEpoch,
                  ),
                  startDate: Value(startDate),
                  endDate: Value(endDate),
                  isAllDay: Value(isAllDay),
                  status: Value(status),
                  meetUrl: Value(meetUrl),
                  microsoftAccount: Value(account),
                  remoteId: Value(remoteId),
                  dirty: const Value(false),
                  createdAt: nowMs,
                  updatedAt: nowMs,
                ),
              );
          eventCount++;
        } else {
          await (_db.update(
            _db.events,
          )..where((t) => t.id.equals(existing.id))).write(
            EventsCompanion(
              calendarId: Value(localCalId),
              title: Value(title),
              notes: Value(notes ?? existing.notes),
              location: Value(location ?? existing.location),
              startUtc: Value(
                isAllDay ? null : startUtc?.millisecondsSinceEpoch,
              ),
              endUtc: Value(isAllDay ? null : endUtc?.millisecondsSinceEpoch),
              startDate: Value(startDate),
              endDate: Value(endDate),
              isAllDay: Value(isAllDay),
              status: Value(status),
              meetUrl: Value(meetUrl ?? existing.meetUrl),
              microsoftAccount: Value(account),
              remoteId: Value(remoteId),
              dirty: const Value(false),
              updatedAt: Value(nowMs),
              // Preserve local-only fields.
              alarmPreset: Value(existing.alarmPreset),
              reminders: Value(existing.reminders),
              visibility: Value(existing.visibility),
              createMeet: Value(existing.createMeet),
              colorId: Value(existing.colorId),
            ),
          );
          eventCount++;
        }
        // TODO(#issue): map Graph recurrence to RRULE when representable; for now store occurrence as single event.
      }
    }
    return eventCount;
  }
}
