part of '../../sync_engine.dart';

extension on SyncEngine {
  Future<int> _pullCalendars(GoogleApiClient client) async {
    final calendars =
        await (_db.select(_db.calendars)..where(
              (c) =>
                  c.source.equals('google') &
                  c.enabled.equals(true) &
                  c.deletedAt.isNull(),
            ))
            .get();
    debugPrint('[sync] pulling ${calendars.length} google calendars');
    var total = 0;
    for (final cal in calendars) {
      if (!_pullableCalendar(cal)) continue;
      debugPrint(
        '[sync] pulling calendar id=${cal.id} remoteId=${cal.remoteId} '
        'name=${cal.name} enabled=${cal.enabled}',
      );
      final token = await _syncValue('cal:${cal.id}:token');
      final remoteId = cal.remoteId;
      if (remoteId == null) {
        debugPrint('[sync] skip calendar with null remoteId');
        continue;
      }
      try {
        if (token == null) {
          total += await _fullCalendarResync(cal, client, keepDirty: true);
        } else {
          final page = await client.eventsList(remoteId, syncToken: token);
          debugPrint(
            '[sync] incremental pull got ${page.items.length} items (has remoteId=${cal.remoteId != null})',
          );
          total += await _mergeEvents(cal, page.items);
          if (page.nextSyncToken != null) {
            await _setSyncValue('cal:${cal.id}:token', page.nextSyncToken!);
          }
        }
        await _setSyncMeta('cal:${cal.id}', error: null);
      } on GoogleApiException catch (e) {
        debugPrint('[sync] calendar pull failed status=${e.status}');
        if (e.isPermissionDenied) {
          _authFailure = true;
          await _setSyncMeta('cal:${cal.id}', error: 'Google ${e.status}');
          rethrow;
        } else if (e.isGone) {
          total += await _fullCalendarResync(cal, client, keepDirty: true);
          await _setSyncMeta('cal:${cal.id}', error: null);
        } else if (e.status == 404) {
          debugPrint('[sync] disabling unreachable calendar ${cal.id}');
          await (_db.update(_db.calendars)..where((x) => x.id.equals(cal.id)))
              .write(const CalendarsCompanion(enabled: Value(false)));
          await _setSyncMeta('cal:${cal.id}', error: 'Google 404');
        } else {
          await _setSyncMeta('cal:${cal.id}', error: 'Google ${e.status}');
          rethrow;
        }
      }
    }
    return total;
  }

  /// Whether [cal] may be pulled under the active account. Rows stamped
  /// with another account belong to that account's loop; null-stamped rows
  /// absent from this run's discovery belong to an unsigned-in account.
  bool _pullableCalendar(Calendar cal) {
    if (account == null) return true;
    if (cal.googleAccount != null) return cal.googleAccount == account;
    final ids = _accountCalendarIds;
    if (ids == null) return true;
    return cal.remoteId == null || ids.contains(cal.remoteId);
  }

  Future<int> _fullCalendarResync(
    Calendar cal,
    GoogleApiClient client, {
    required bool keepDirty,
  }) async {
    final page = await client.eventsList(
      cal.remoteId ?? cal.id,
      timeMin: _iso(_now() - 30 * msPerDay),
      timeMax: _iso(_now() + 90 * msPerDay),
    );
    debugPrint(
      '[sync] full resync got ${page.items.length} items (has remoteId=${cal.remoteId != null})',
    );
    return _db.transaction(() async {
      // Drop synced rows in the window; keep dirty local rows.
      final local =
          await (_db.select(_db.events)..where(
                (e) => e.calendarId.equals(cal.id) & e.deletedAt.isNull(),
              ))
              .get();
      for (final e in local) {
        if (e.remoteId != null && !(keepDirty && e.dirty)) {
          await (_db.delete(
            _db.occurrenceCache,
          )..where((o) => o.eventId.equals(e.id))).go();
          await (_db.delete(_db.events)..where((x) => x.id.equals(e.id))).go();
        }
      }
      final n = await _mergeEvents(cal, page.items);
      debugPrint('[sync] full resync merged $n events');
      if (page.nextSyncToken != null) {
        await _setSyncValue('cal:${cal.id}:token', page.nextSyncToken!);
      }
      return n;
    });
  }

  Future<int> _mergeEvents(
    Calendar cal,
    List<Map<String, dynamic>> items,
  ) async {
    var n = 0;
    for (final g in items) {
      final remoteId = g['id'] as String?;
      if (remoteId == null) continue;
      final existing =
          await (_db.select(_db.events)..where(
                (e) =>
                    e.remoteId.equals(remoteId) & e.calendarId.equals(cal.id),
              ))
              .getSingleOrNull();
      if (g['status'] == 'cancelled') {
        if (existing != null && !existing.dirty) {
          await (_db.update(
            _db.events,
          )..where((e) => e.id.equals(existing.id))).write(
            EventsCompanion(
              status: const Value('cancelled'),
              deletedAt: Value(_now()),
              dirty: const Value(false),
            ),
          );
        }
        continue;
      }
      late String localId;
      if (existing == null) {
        final mapped = eventFromGoogle(g, cal.id, newId());
        await _db
            .into(_db.events)
            .insert(mapped.companion.copyWith(googleAccount: Value(account)));
        localId = mapped.companion.id.value;
        n++;
      } else if (!existing.dirty) {
        // Last-writer-wins on shared fields; local-only fields preserved
        // by only writing shared columns.
        final mapped = eventFromGoogle(g, cal.id, existing.id);
        await (_db.update(
          _db.events,
        )..where((e) => e.id.equals(existing.id))).write(
          mapped.companion.copyWith(alarmPreset: const Value.absent()),
        );
        localId = existing.id;
        n++;
      } else {
        localId = existing.id;
      }
      final hangout = g['hangoutLink'] as String?;
      if (hangout != null) {
        await (_db.update(_db.events)..where((e) => e.id.equals(localId)))
            .write(EventsCompanion(meetUrl: Value(hangout)));
      }
      await _mergeAttendees(localId, g);
    }
    return n;
  }

  Future<void> _mergeAttendees(String eventId, Map<String, dynamic> g) async {
    final atts = g['attendees'] as List?;
    if (atts == null) return;
    final organizerEmail = (g['organizer'] as Map?)?['email'] as String?;
    await _db.transaction(() async {
      await (_db.delete(
        _db.eventAttendees,
      )..where((a) => a.eventId.equals(eventId))).go();
      for (final a in atts) {
        final m = a as Map<String, dynamic>;
        final email = m['email'] as String?;
        if (email == null || email.isEmpty) continue;
        // SECURITY: isSelf/isOrganizer come from the signed-in user's own
        // Google data; never trust client-side state for access control.
        final isSelfFlag =
            m['self'] == true ||
            (account != null && email.toLowerCase() == account!.toLowerCase());
        final isOrganizerFlag =
            m['organizer'] == true ||
            (organizerEmail != null &&
                email.toLowerCase() == organizerEmail.toLowerCase());
        await _db
            .into(_db.eventAttendees)
            .insert(
              EventAttendeesCompanion.insert(
                id: newId(),
                eventId: eventId,
                email: email,
                name: Value(m['displayName'] as String?),
                rsvp: Value(m['responseStatus'] as String?),
                isOrganizer: Value(isOrganizerFlag),
                isSelf: Value(isSelfFlag),
              ),
            );
      }
    });
  }
}
