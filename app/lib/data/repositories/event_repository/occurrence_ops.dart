part of '../event_repository.dart';

extension EventRepositoryOccurrenceOps on EventRepository {
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
}
