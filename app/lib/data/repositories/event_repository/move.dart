part of '../event_repository.dart';

extension EventRepositoryMove on EventRepository {
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
}
