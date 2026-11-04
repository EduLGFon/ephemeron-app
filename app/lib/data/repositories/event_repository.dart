// Event and calendar repository: CRUD, recurrence scope ops (PLAN 5.4),
// outbox rows, occurrence-cache invalidation.
// UI reads occurrences via OccurrenceRepository streams.
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/outbox_helper.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/domain/sources/source_move.dart';

enum EditScope { single, following, all }

class EventRepository {
  EventRepository(this._db, this._occ);

  final AppDatabase _db;
  final OccurrenceRepository _occ;

  Future<void> _enqueue(String entityId, String op, {String? payload}) =>
      enqueueOutbox(
        _db,
        entity: 'event',
        entityId: entityId,
        op: op,
        payload: payload,
      );

  Future<void> _enqueueRemoteDelete({
    required String eventId,
    required String calendarRemoteId,
    required String eventRemoteId,
    required String account,
  }) {
    return enqueueOutbox(
      _db,
      entity: 'event_remote',
      entityId: eventId,
      op: 'delete',
      payload: jsonEncode({
        'account': account,
        'calendarRemoteId': calendarRemoteId,
        'eventRemoteId': eventRemoteId,
      }),
    );
  }

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

  /// Next calendar day for a `YYYY-MM-DD` string.
  String _nextDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return date;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return date;
    return _dateOf(DateTime.utc(year, month, day + 1).millisecondsSinceEpoch);
  }

  Future<String?> _accountOfCalendar(String calendarId) async {
    return (await _calendar(calendarId))?.googleAccount;
  }

  Future<Calendar?> _calendar(String calendarId) {
    return (_db.select(
      _db.calendars,
    )..where((c) => c.id.equals(calendarId))).getSingleOrNull();
  }

  /// Moves an event (and its series) to [targetCalendarId].
  ///
  /// Same-account Google calendars use the Calendar API move endpoint. A move
  /// to another account, or to/from a local calendar, becomes a local copy
  /// plus a queued delete of the old remote row. Recurring series cannot move
  /// across accounts because Google has no single-token cross-account move.
  Future<void> moveEventToCalendar(
    String eventId,
    String targetCalendarId,
  ) async {
    final event = await _master(eventId);
    if (event.calendarId == targetCalendarId) return;
    final sourceCal = await _calendar(event.calendarId);
    final targetCal = await _calendar(targetCalendarId);
    if (targetCal == null) {
      throw SourceMoveException('Calendar not found.');
    }
    if (targetCal.readOnly) {
      throw SourceMoveException('That calendar is read-only.');
    }
    final sourceAccount = event.googleAccount ?? sourceCal?.googleAccount;
    final targetAccount = targetCal.googleAccount;
    final targetIsGoogle =
        targetCal.source == 'google' && targetCal.remoteId != null;
    final sourceRemoteCal = sourceCal?.source == 'google'
        ? sourceCal?.remoteId
        : null;
    final sourceRemoteId = event.remoteId;
    final wasDirty = event.dirty;
    final recurring = event.rrule != null && event.rrule!.isNotEmpty;
    final exceptions = recurring
        ? await exceptionsOf(event.id)
        : const <Event>[];
    if (recurring && targetIsGoogle && sourceAccount != targetAccount) {
      throw SourceMoveException(
        'Move recurring series within the same account.',
      );
    }
    // If an earlier move is still queued, keep its original source instead
    // of treating the intermediate calendar as the remote home.
    var remoteFrom = sourceRemoteCal;
    final pendingMove =
        await (_db.select(_db.outbox)..where(
              (o) =>
                  o.entity.equals('event') &
                  o.entityId.equals(event.id) &
                  o.op.equals('move'),
            ))
            .getSingleOrNull();
    if (pendingMove?.payload != null) {
      try {
        final p = jsonDecode(pendingMove!.payload!) as Map<String, dynamic>;
        remoteFrom = (p['fromRemoteCalendarId'] as String?) ?? remoteFrom;
      } catch (_) {
        // Keep the current calendar as the source.
      }
    }

    final useRemoteMove =
        sourceAccount == targetAccount &&
        targetIsGoogle &&
        remoteFrom != null &&
        sourceRemoteId != null;
    final now = nowMs();
    final entityIds = [event.id, for (final ex in exceptions) ex.id];
    await (_db.delete(_db.outbox)
          ..where((o) => o.entity.equals('event') & o.entityId.isIn(entityIds)))
        .go();

    await _db.transaction(() async {
      if (useRemoteMove) {
        await _writeEventSource(
          event.id,
          targetCalendarId,
          targetAccount,
          dirty: true,
          clearRemote: false,
          now: now,
        );
        for (final ex in exceptions) {
          await _writeEventSource(
            ex.id,
            targetCalendarId,
            targetAccount,
            dirty: ex.dirty,
            clearRemote: false,
            now: now,
          );
        }
        await _enqueue(
          event.id,
          'move',
          payload: jsonEncode({
            'fromCalendarId': event.calendarId,
            'fromRemoteCalendarId': remoteFrom,
          }),
        );
        // A move endpoint only moves the remote row. Re-push local edits
        // that would otherwise be lost when their update op is replaced.
        if (wasDirty) await _enqueue(event.id, 'update');
        for (final ex in exceptions) {
          if (ex.dirty) await _enqueue(ex.id, 'update');
        }
        return;
      }

      await _writeEventSource(
        event.id,
        targetCalendarId,
        targetAccount,
        dirty: targetIsGoogle,
        clearRemote: true,
        now: now,
      );
      for (final ex in exceptions) {
        await _writeEventSource(
          ex.id,
          targetCalendarId,
          targetAccount,
          dirty: targetIsGoogle,
          clearRemote: true,
          now: now,
        );
      }
      if (targetIsGoogle) {
        await _enqueue(event.id, 'update');
        for (final ex in exceptions) {
          await _enqueue(ex.id, 'update');
        }
      }
      final remoteFromCal = remoteFrom;
      if (remoteFromCal != null && sourceAccount != null) {
        if (sourceRemoteId != null) {
          await _enqueueRemoteDelete(
            eventId: event.id,
            calendarRemoteId: remoteFromCal,
            eventRemoteId: sourceRemoteId,
            account: sourceAccount,
          );
        }
        for (final ex in exceptions) {
          final remoteId = ex.remoteId;
          if (remoteId == null) continue;
          await _enqueueRemoteDelete(
            eventId: ex.id,
            calendarRemoteId: remoteFromCal,
            eventRemoteId: remoteId,
            account: sourceAccount,
          );
        }
      }
    });
    await _occ.invalidateEvent(event.id);
  }

  Future<void> _writeEventSource(
    String eventId,
    String calendarId,
    String? account, {
    required bool dirty,
    required bool clearRemote,
    required int now,
  }) {
    return (_db.update(_db.events)..where((e) => e.id.equals(eventId))).write(
      EventsCompanion(
        calendarId: Value(calendarId),
        googleAccount: Value(account),
        remoteId: clearRemote ? const Value(null) : const Value.absent(),
        remoteEtag: clearRemote ? const Value(null) : const Value.absent(),
        dirty: Value(dirty),
        updatedAt: Value(now),
      ),
    );
  }

  Future<Event> _master(String id) async {
    return (dbSelect()..where((e) => e.id.equals(id))).getSingle();
  }

  SimpleSelectStatement<$EventsTable, Event> dbSelect() =>
      _db.select(_db.events);

  Future<List<Event>> exceptionsOf(String masterId) {
    return (dbSelect()..where(
          (e) => e.recurringMasterId.equals(masterId) & e.deletedAt.isNull(),
        ))
        .get();
  }

  /// Global-search hits over live events, newest first.
  Future<List<Event>> searchEvents(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = sanitizeSearch(q);
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    return (dbSelect()
          ..where(
            (e) =>
                e.deletedAt.isNull() &
                (e.title.like(like) |
                    e.location.like(like) |
                    e.notes.like(like)),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.updatedAt)])
          ..limit(limit))
        .get();
  }

  /// Deletes one occurrence, following ones, or the whole series.
  Future<void> deleteOccurrence(
    String masterId,
    DateTime originalStartUtc, {
    required EditScope scope,
  }) async {
    final master = await _master(masterId);
    final cutMs = originalStartUtc.toUtc().millisecondsSinceEpoch;
    switch (scope) {
      case EditScope.single:
        await _upsertException(
          master,
          cutMs,
          const EventsCompanion(status: Value('cancelled')),
        );
        await _enqueue(masterId, 'update');
      case EditScope.following:
        final first = _seriesFirstStart(master);
        if (first != null && cutMs <= first) {
          await deleteEvent(masterId);
          return;
        }
        await _truncateMaster(master, cutMs);
        await _enqueue(masterId, 'update');
      case EditScope.all:
        await deleteEvent(masterId);
    }
    await _occ.invalidateEvent(masterId);
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

  /// Edits one occurrence, following ones (split), or the whole series.
  ///
  /// Returns the id of the row that received the edit: the master for
  /// [EditScope.all], the exception for [EditScope.single], or the new split
  /// master for [EditScope.following].
  Future<String> editOccurrence(
    String masterId,
    DateTime originalStartUtc, {
    required EditScope scope,
    String? title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? startDate,
    String? endDate,
    String? location,
    String? colorId,
    String? tzId,
    bool? createMeet,
    String? Function()? rrule,
    bool resetExceptions = false,
    String? Function()? reminders,
    String? Function()? alarmPreset,
    String? Function()? notes,
  }) async {
    final master = await _master(masterId);
    final cutMs = originalStartUtc.toUtc().millisecondsSinceEpoch;
    final notePatch = notes == null
        ? const Value<String?>.absent()
        : Value<String?>(notes());
    String affectedId;
    switch (scope) {
      case EditScope.single:
        affectedId = await _upsertException(
          master,
          cutMs,
          EventsCompanion(
            title: title == null ? const Value.absent() : Value(title),
            startUtc: startUtc == null
                ? const Value.absent()
                : Value(startUtc.toUtc().millisecondsSinceEpoch),
            endUtc: endUtc == null
                ? const Value.absent()
                : Value(endUtc.toUtc().millisecondsSinceEpoch),
            startDate: startDate == null
                ? const Value.absent()
                : Value(startDate),
            endDate: endDate == null ? const Value.absent() : Value(endDate),
            location: location == null ? const Value.absent() : Value(location),
            colorId: colorId == null ? const Value.absent() : Value(colorId),
            tzId: tzId == null ? const Value.absent() : Value(tzId),
            createMeet: createMeet == null
                ? const Value.absent()
                : Value(createMeet),
            notes: notePatch,
          ),
        );
        await _enqueue(masterId, 'update');
      case EditScope.following:
        affectedId = await _splitMaster(
          master,
          cutMs,
          title: title,
          startUtc: startUtc,
          endUtc: endUtc,
          location: location,
          rrule: rrule == null ? null : rrule(),
          startDate: startDate,
          endDate: endDate,
          notes: notePatch,
        );
        await _enqueue(masterId, 'update');
      case EditScope.all:
        await (_db.update(
          _db.events,
        )..where((e) => e.id.equals(masterId))).write(
          EventsCompanion(
            title: title == null ? const Value.absent() : Value(title),
            startUtc: startUtc == null
                ? const Value.absent()
                : Value(startUtc.toUtc().millisecondsSinceEpoch),
            endUtc: endUtc == null
                ? const Value.absent()
                : Value(endUtc.toUtc().millisecondsSinceEpoch),
            startDate: startDate == null
                ? const Value.absent()
                : Value(startDate),
            endDate: endDate == null ? const Value.absent() : Value(endDate),
            location: location == null ? const Value.absent() : Value(location),
            colorId: colorId == null ? const Value.absent() : Value(colorId),
            tzId: tzId == null ? const Value.absent() : Value(tzId),
            createMeet: createMeet == null
                ? const Value.absent()
                : Value(createMeet),
            rrule: rrule == null ? const Value.absent() : Value(rrule()),
            reminders: reminders == null
                ? const Value.absent()
                : Value(reminders()),
            alarmPreset: alarmPreset == null
                ? const Value.absent()
                : Value(alarmPreset()),
            notes: notePatch,
            updatedAt: Value(nowMs()),
            dirty: const Value(true),
          ),
        );
        if (resetExceptions) {
          for (final ex in await exceptionsOf(masterId)) {
            await (_db.update(
              _db.events,
            )..where((e) => e.id.equals(ex.id))).write(
              EventsCompanion(
                deletedAt: Value(nowMs()),
                updatedAt: Value(nowMs()),
              ),
            );
          }
        }
        await _enqueue(masterId, 'update');
        affectedId = masterId;
    }
    await _occ.invalidateEvent(masterId);
    return affectedId;
  }

  Future<String> _upsertException(
    Event master,
    int originalStartMs,
    EventsCompanion changes,
  ) async {
    final existing =
        await (dbSelect()..where(
              (e) =>
                  e.recurringMasterId.equals(master.id) &
                  e.originalStart.equals(originalStartMs) &
                  e.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    final now = nowMs();
    if (existing == null) {
      final id = newId();
      await _db
          .into(_db.events)
          .insert(
            changes.copyWith(
              id: Value(id),
              calendarId: Value(master.calendarId),
              googleAccount: Value(master.googleAccount),
              title: changes.title.present
                  ? changes.title
                  : Value(master.title),
              notes: changes.notes.present
                  ? changes.notes
                  : Value(master.notes),
              recurringMasterId: Value(master.id),
              originalStart: Value(originalStartMs),
              startUtc: changes.startUtc.present
                  ? changes.startUtc
                  : Value(originalStartMs),
              endUtc: changes.endUtc.present
                  ? changes.endUtc
                  : Value(
                      originalStartMs +
                          ((master.endUtc ?? originalStartMs) -
                              (master.startUtc ?? originalStartMs)),
                    ),
              startDate: changes.startDate.present
                  ? changes.startDate
                  : Value(master.startDate),
              endDate: changes.endDate.present
                  ? changes.endDate
                  : Value(master.endDate),
              status: changes.status.present
                  ? changes.status
                  : const Value('confirmed'),
              isAllDay: Value(master.isAllDay),
              tzId: Value(master.tzId),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      return id;
    } else {
      await (_db.update(
        _db.events,
      )..where((e) => e.id.equals(existing.id))).write(
        changes.copyWith(updatedAt: Value(now), dirty: const Value(true)),
      );
      return existing.id;
    }
  }

  /// Sets master UNTIL to the instant before [cutMs] (date form all-day),
  /// drops COUNT, removes later exceptions. Collapses to non-recurring
  /// when only the first occurrence remains.
  Future<void> _truncateMaster(Event master, int cutMs) async {
    final until = master.isAllDay
        ? _dateOf(cutMs - msPerDay)
        : _untilUtc(cutMs - 1000);
    final base = _stripCount(master.rrule ?? '');
    final rrule = base.isEmpty ? '' : '$base;UNTIL=$until';
    await (_db.update(_db.events)..where((e) => e.id.equals(master.id))).write(
      EventsCompanion(
        rrule: Value(rrule.isEmpty ? null : rrule),
        updatedAt: Value(nowMs()),
        dirty: const Value(true),
      ),
    );
    for (final ex in await exceptionsOf(master.id)) {
      if ((ex.originalStart ?? 0) >= cutMs) {
        await (_db.update(_db.events)..where((e) => e.id.equals(ex.id))).write(
          EventsCompanion(deletedAt: Value(nowMs()), updatedAt: Value(nowMs())),
        );
      }
    }
  }

  Future<String> _splitMaster(
    Event master,
    int cutMs, {
    String? title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? startDate,
    String? endDate,
    String? location,
    String? rrule,
    Value<String?> notes = const Value.absent(),
  }) async {
    await _truncateMaster(master, cutMs);
    final durationMs =
        (master.endUtc ?? master.startUtc ?? cutMs) -
        (master.startUtc ?? cutMs);
    final newStart = startUtc?.toUtc().millisecondsSinceEpoch ?? cutMs;
    final newEnd =
        endUtc?.toUtc().millisecondsSinceEpoch ?? (newStart + durationMs);
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            id: id,
            calendarId: master.calendarId,
            title: Value(title ?? master.title),
            startUtc: Value(newStart),
            endUtc: Value(newEnd),
            startDate: Value(startDate ?? master.startDate),
            endDate: Value(endDate ?? master.endDate),
            isAllDay: Value(master.isAllDay),
            tzId: Value(master.tzId),
            rrule: Value(rrule ?? _stripCount(master.rrule ?? '')),
            location: Value(location ?? master.location),
            notes: notes.present ? notes : Value(master.notes),
            dirty: const Value(true),
            googleAccount: Value(master.googleAccount),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue(id, 'create');
    return id;
  }

  int? _seriesFirstStart(Event master) => master.startUtc;

  String _stripCount(String rrule) {
    final parts = rrule
        .split(';')
        .where((p) => !p.toUpperCase().startsWith('COUNT='));
    return parts.join(';');
  }

  String _untilUtc(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    String p(int v, int w) => v.toString().padLeft(w, '0');
    return '${p(d.year, 4)}${p(d.month, 2)}${p(d.day, 2)}T${p(d.hour, 2)}${p(d.minute, 2)}${p(d.second, 2)}Z';
  }

  String _dateOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // Calendars.

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
    return resolveSelf(await attendeesOf(eventId), accountEmails);
  }

  /// Pure self-resolution over already-loaded rows (see [selfAttendeeOf]).
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

  /// Returns events in [calendarId] overlapping [startUtc, endUtc).
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
