part of '../event_repository.dart';

mixin _EventMoveOps on _EventRepositoryBase {
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
}
