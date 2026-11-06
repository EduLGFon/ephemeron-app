part of '../sync_engine.dart';

extension on SyncEngine {
  // Discovery: mirror the remote calendar/task-list catalog locally so
  // the first sync after sign-in has something to pull into. Local-only
  // rows are never touched; renamed remotes update in place when clean.

  Future<(int, int)> _syncCalendarList(GoogleApiClient client) async {
    final remote = await client.calendarList();
    debugPrint('[sync] calendarList returned ${remote.length} items');
    _accountCalendarIds = account == null
        ? null
        : {
            for (final c in remote) c['id'] as String?,
          }.whereType<String>().toSet();
    final now = _now();
    var created = 0;
    for (final c in remote) {
      final id = c['id'] as String?;
      if (id == null || c['deleted'] == true) continue;
      final name = (c['summary'] as String?)?.trim();
      var existing = await (_db.select(
        _db.calendars,
      )..where((t) => t.remoteId.equals(id))).getSingleOrNull();
      // Repair legacy rows created before remoteId was persisted.
      if (existing == null && name != null && name.isNotEmpty) {
        existing =
            await (_db.select(_db.calendars)..where(
                  (t) =>
                      t.source.equals('google') &
                      t.remoteId.isNull() &
                      t.name.equals(name),
                ))
                .getSingleOrNull();
        if (existing != null) {
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(existing!.id))).write(
            CalendarsCompanion(
              remoteId: Value(id),
              updatedAt: Value(now),
              googleAccount: Value(account),
            ),
          );
          debugPrint(
            '[sync] repaired legacy calendar remoteId id=${existing.id}',
          );
        }
      }
      if (existing == null) {
        await _db
            .into(_db.calendars)
            .insert(
              CalendarsCompanion.insert(
                id: newId(),
                remoteId: Value(id),
                name: (name == null || name.isEmpty) ? id : name,
                color: Value(_calendarColorOf(c)),
                source: const Value('google'),
                googleAccount: Value(account),
                readOnly: Value((c['accessRole'] as String?) == 'reader'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else {
        // Keep the ownership stamp current: a remote id belongs to exactly
        // one account (shared calendars may flap; either token can pull).
        if (account != null && existing.googleAccount != account) {
          await (_db.update(
            _db.calendars,
          )..where((t) => t.id.equals(existing!.id))).write(
            CalendarsCompanion(
              googleAccount: Value(account),
              updatedAt: Value(now),
            ),
          );
        }
        if (!existing.dirty && name != null && name.isNotEmpty) {
          final color = _calendarColorOf(c);
          final update = CalendarsCompanion(
            name: Value(name),
            updatedAt: Value(now),
            color: color == null ? const Value.absent() : Value(color),
          );
          if (existing.name != name || existing.color != color) {
            await (_db.update(
              _db.calendars,
            )..where((t) => t.id.equals(existing!.id))).write(update);
          }
        }
      }
    }
    // Remove duplicate google calendars left by earlier (buggy) runs.
    final all = await (_db.select(
      _db.calendars,
    )..where((c) => c.source.equals('google'))).get();
    final seen = <String>{};
    for (final c in all) {
      final key = c.remoteId;
      if (key == null) continue;
      if (seen.contains(key)) {
        await (_db.delete(_db.calendars)..where((x) => x.id.equals(c.id))).go();
      } else {
        seen.add(key);
      }
    }
    // Disable calendars of THIS account that are no longer reachable, but
    // only when the remote list is non-empty (an empty result is ambiguous).
    // Never touch another account's rows: their loop owns them.
    if (remote.isNotEmpty && account != null) {
      final remoteIds = {for (final c in remote) c['id'] as String?}
        ..removeWhere((x) => x == null);
      for (final c in all) {
        if (c.googleAccount == account &&
            c.remoteId != null &&
            !remoteIds.contains(c.remoteId)) {
          await (_db.update(_db.calendars)..where((x) => x.id.equals(c.id)))
              .write(const CalendarsCompanion(enabled: Value(false)));
        }
      }
    }
    return (remote.length, created);
  }

  Future<(int, int)> _syncTaskLists(GoogleApiClient client) async {
    final remote = await client.taskLists();
    debugPrint('[sync] taskLists returned ${remote.length} items');
    _accountListIds = account == null
        ? null
        : {
            for (final l in remote) l['id'] as String?,
          }.whereType<String>().toSet();
    final now = _now();
    var created = 0;
    for (final l in remote) {
      final id = l['id'] as String?;
      if (id == null) continue;
      final name = (l['title'] as String?)?.trim();
      // A remote id belongs to exactly one local row. Duplicate rows from
      // older runs must not make discovery throw or insert another copy.
      final linked = await (_db.select(
        _db.taskLists,
      )..where((t) => t.remoteId.equals(id))).get();
      final existing = linked.where((row) => row.deletedAt == null).firstOrNull;
      if (existing == null) {
        if (linked.isNotEmpty) {
          // The only local copy is a tombstone awaiting remote delete. Do not
          // resurrect it; the queued delete (or the next sync) owns it.
          continue;
        }
        await _db
            .into(_db.taskLists)
            .insert(
              TaskListsCompanion.insert(
                id: newId(),
                remoteId: Value(id),
                name: (name == null || name.isEmpty) ? id : name,
                googleAccount: Value(account),
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else {
        if (account != null && existing.googleAccount != account) {
          await (_db.update(
            _db.taskLists,
          )..where((t) => t.id.equals(existing.id))).write(
            TaskListsCompanion(
              googleAccount: Value(account),
              updatedAt: Value(now),
            ),
          );
        }
        if (!existing.dirty && name != null && name.isNotEmpty) {
          await (_db.update(
            _db.taskLists,
          )..where((t) => t.id.equals(existing.id))).write(
            TaskListsCompanion(name: Value(name), updatedAt: Value(now)),
          );
        }
      }
    }
    return (remote.length, created);
  }

  // Pull.

  /// Google calendarList color: backgroundColor hex wins, colorId palette
  /// id as fallback. Returns null when the entry carries no color so the
  /// occurrence builder can apply its stable per-calendar fallback.
  String? _calendarColorOf(Map<String, dynamic> c) {
    final bg = c['backgroundColor'] as String?;
    if (bg != null && bg.isNotEmpty) return bg;
    final id = c['colorId'] as String?;
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

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

  Future<int> _pullTasks(GoogleApiClient client) async {
    final lists = await (_db.select(
      _db.taskLists,
    )..where((l) => l.deletedAt.isNull())).get();
    debugPrint(
      '[sync] pulling ${lists.length} task lists '
      '(${lists.where((l) => l.remoteId != null).length} remote)',
    );
    var total = 0;
    for (final list in lists) {
      // Device-only lists have no remote counterpart; skip them instead
      // of querying Google with a local UUID (which 404s and fails sync).
      final remoteId = list.remoteId;
      if (remoteId == null) continue;
      if (!_pullableTaskList(list)) continue;
      var updatedMin = await _syncValue('tasks:${list.id}:updatedMin');
      try {
        var page = await client.tasksList(remoteId, updatedMin: updatedMin);
        if (updatedMin != null && page.items.isEmpty) {
          page = await client.tasksList(remoteId);
          debugPrint(
            '[sync] tasksList retry without updatedMin got ${page.items.length} items',
          );
        }
        debugPrint('[sync] tasksList got ${page.items.length} items');
        for (final g in page.items) {
          if (await _mergeTask(list, g)) total++;
        }
        if (page.nextUpdatedMin != null) {
          await _setSyncValue(
            'tasks:${list.id}:updatedMin',
            page.nextUpdatedMin!,
          );
        }
        await _setSyncMeta('tasks:${list.id}', error: null);
      } on GoogleApiException catch (e) {
        debugPrint('[sync] tasks pull failed status=${e.status}');
        if (e.isPermissionDenied) {
          // Calendar-only grant hitting Tasks, or revoked access. Keep the
          // rows; the reconnect banner owns this state.
          _authFailure = true;
        }
        await _setSyncMeta('tasks:${list.id}', error: 'Google ${e.status}');
      }
    }
    return total;
  }

  /// Whether [list] may be pulled under the active account. Same rule as
  /// calendars: stamped rows belong to their account's loop, null-stamped
  /// rows absent from this run's discovery belong elsewhere.
  bool _pullableTaskList(TaskList list) {
    if (account == null) return true;
    if (list.googleAccount != null) return list.googleAccount == account;
    final ids = _accountListIds;
    if (ids == null) return true;
    return ids.contains(list.remoteId);
  }

  Future<bool> _mergeTask(TaskList list, Map<String, dynamic> g) async {
    final remoteId = g['id'] as String?;
    if (remoteId == null) return false;
    final existing = await (_db.select(
      _db.tasks,
    )..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
    if (existing == null) {
      final mapped = taskFromGoogle(g, list.id, newId());
      await _db
          .into(_db.tasks)
          .insert(mapped.companion.copyWith(googleAccount: Value(account)));
      return true;
    } else if (!existing.dirty) {
      final mapped = taskFromGoogle(g, list.id, existing.id);
      // Preserve local-only fields: dueTime, priority, tags stay.
      await (_db.update(
        _db.tasks,
      )..where((t) => t.id.equals(existing.id))).write(
        mapped.companion.copyWith(
          dueTime: Value(existing.dueTime),
          priority: Value(existing.priority),
          durationMin: Value(existing.durationMin),
          rrule: Value(existing.rrule),
          plannedStart: Value(existing.plannedStart),
          plannedEnd: Value(existing.plannedEnd),
          seriesId: Value(existing.seriesId),
          recurrenceKey: Value(existing.recurrenceKey),
        ),
      );
      return true;
    }
    return false;
  }

  Future<String?> _remoteCalendarId(String localId) async {
    final cal = await (_db.select(
      _db.calendars,
    )..where((c) => c.id.equals(localId))).getSingleOrNull();
    return cal?.remoteId;
  }

  Future<String?> _remoteTaskListId(String? localId) async {
    if (localId == null) return null;
    final list = await (_db.select(
      _db.taskLists,
    )..where((l) => l.id.equals(localId))).getSingleOrNull();
    return list?.remoteId;
  }

  Future<String?> _syncValue(String key) async {
    final row = await (_db.select(
      _db.syncState,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSyncValue(String key, String value) async {
    final now = _now();
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: key,
            value: Value(value),
            lastSyncAt: Value(now),
          ),
        );
  }

  Future<void> _setSyncMeta(String key, {String? error}) async {
    await _db
        .into(_db.syncState)
        .insertOnConflictUpdate(
          SyncStateCompanion.insert(
            key: '$key:meta',
            lastSyncAt: Value(_now()),
            lastError: Value(error),
          ),
        );
  }
}
