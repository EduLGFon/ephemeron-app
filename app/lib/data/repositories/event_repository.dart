// Event and calendar repository: CRUD, recurrence scope ops (PLAN 5.4),
// outbox rows, occurrence-cache invalidation.
// UI reads occurrences via OccurrenceRepository streams.
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';

enum EditScope { single, following, all }

class EventRepository {
  EventRepository(this._db, this._occ);

  final AppDatabase _db;
  final OccurrenceRepository _occ;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<void> _enqueue(String entityId, String op) {
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: newId(),
            entity: 'event',
            entityId: entityId,
            op: op,
            createdAt: _now(),
          ),
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
  }) async {
    final id = newId();
    final now = _now();
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
            endDate: Value(endDate ?? startDate),
            isAllDay: Value(allDay),
            tzId: Value(tzId),
            rrule: Value(rrule),
            location: Value(location),
            notes: Value(notes),
            colorId: Value(colorId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue(id, 'create');
    return id;
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
    final stripped = q.replaceAll('%', '').replaceAll('_', '').trim();
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
    final now = _now();
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
  Future<void> editOccurrence(
    String masterId,
    DateTime originalStartUtc, {
    required EditScope scope,
    String? title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? location,
    String? Function()? rrule,
    bool resetExceptions = false,
  }) async {
    final master = await _master(masterId);
    final cutMs = originalStartUtc.toUtc().millisecondsSinceEpoch;
    switch (scope) {
      case EditScope.single:
        await _upsertException(
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
            location: location == null ? const Value.absent() : Value(location),
          ),
        );
        await _enqueue(masterId, 'update');
      case EditScope.following:
        await _splitMaster(
          master,
          cutMs,
          title: title,
          startUtc: startUtc,
          endUtc: endUtc,
          location: location,
          rrule: rrule == null ? null : rrule(),
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
            location: location == null ? const Value.absent() : Value(location),
            rrule: rrule == null ? const Value.absent() : Value(rrule()),
            updatedAt: Value(_now()),
            dirty: const Value(true),
          ),
        );
        if (resetExceptions) {
          for (final ex in await exceptionsOf(masterId)) {
            await (_db.update(
              _db.events,
            )..where((e) => e.id.equals(ex.id))).write(
              EventsCompanion(
                deletedAt: Value(_now()),
                updatedAt: Value(_now()),
              ),
            );
          }
        }
        await _enqueue(masterId, 'update');
    }
    await _occ.invalidateEvent(masterId);
  }

  Future<void> _upsertException(
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
    final now = _now();
    if (existing == null) {
      await _db
          .into(_db.events)
          .insert(
            changes.copyWith(
              id: Value(newId()),
              calendarId: Value(master.calendarId),
              title: changes.title.present
                  ? changes.title
                  : Value(master.title),
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
              status: changes.status.present
                  ? changes.status
                  : const Value('confirmed'),
              isAllDay: Value(master.isAllDay),
              tzId: Value(master.tzId),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (_db.update(
        _db.events,
      )..where((e) => e.id.equals(existing.id))).write(
        changes.copyWith(updatedAt: Value(now), dirty: const Value(true)),
      );
    }
  }

  /// Sets master UNTIL to the instant before [cutMs] (date form all-day),
  /// drops COUNT, removes later exceptions. Collapses to non-recurring
  /// when only the first occurrence remains.
  Future<void> _truncateMaster(Event master, int cutMs) async {
    final until = master.isAllDay
        ? _dateOf(cutMs - 86400000)
        : _untilUtc(cutMs - 1000);
    final base = _stripCount(master.rrule ?? '');
    final rrule = base.isEmpty ? '' : '$base;UNTIL=$until';
    await (_db.update(_db.events)..where((e) => e.id.equals(master.id))).write(
      EventsCompanion(
        rrule: Value(rrule.isEmpty ? null : rrule),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
    for (final ex in await exceptionsOf(master.id)) {
      if ((ex.originalStart ?? 0) >= cutMs) {
        await (_db.update(_db.events)..where((e) => e.id.equals(ex.id))).write(
          EventsCompanion(deletedAt: Value(_now()), updatedAt: Value(_now())),
        );
      }
    }
  }

  Future<void> _splitMaster(
    Event master,
    int cutMs, {
    String? title,
    DateTime? startUtc,
    DateTime? endUtc,
    String? location,
    String? rrule,
  }) async {
    await _truncateMaster(master, cutMs);
    final durationMs =
        (master.endUtc ?? master.startUtc ?? cutMs) -
        (master.startUtc ?? cutMs);
    final newStart = startUtc?.toUtc().millisecondsSinceEpoch ?? cutMs;
    final newEnd =
        endUtc?.toUtc().millisecondsSinceEpoch ?? (newStart + durationMs);
    final id = newId();
    final now = _now();
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion.insert(
            id: id,
            calendarId: master.calendarId,
            title: Value(title ?? master.title),
            startUtc: Value(newStart),
            endUtc: Value(newEnd),
            isAllDay: Value(master.isAllDay),
            tzId: Value(master.tzId),
            rrule: Value(rrule ?? _stripCount(master.rrule ?? '')),
            location: Value(location ?? master.location),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _enqueue(id, 'create');
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

  Future<String> createCalendar(
    String name, {
    String source = 'device',
    String? color,
  }) async {
    final id = newId();
    final now = _now();
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
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> setCalendarEnabled(String id, bool enabled) async {
    await (_db.update(_db.calendars)..where((c) => c.id.equals(id))).write(
      CalendarsCompanion(enabled: Value(enabled), updatedAt: Value(_now())),
    );
  }

  Stream<List<Event>> watchExceptions(String masterId) {
    return (dbSelect()..where((e) => e.recurringMasterId.equals(masterId)))
        .watch();
  }
}
