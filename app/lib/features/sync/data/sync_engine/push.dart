part of '../sync_engine.dart';

extension on SyncEngine {
  Future<int> _pushOutbox(GoogleApiClient client) async {
    final ops =
        await (_db.select(_db.outbox)
              ..where(
                (o) =>
                    o.nextTryAt.isNull() |
                    o.nextTryAt.isSmallerOrEqualValue(_now()),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
            .get();
    var done = 0;
    for (final op in ops) {
      // Backend-owned entities (habits, focus) have their own engine and
      // cursors; the Google engine must leave their outbox rows alone.
      if (!SyncEngine._isGoogleEntity(op.entity)) continue;
      // Multi-account: a row stamped with another signed-in account is
      // left due for that account's loop. Never push it under this token:
      // a wrong-account call 404s and must not delete the row.
      if (!await _ownedByActiveAccount(op)) continue;
      try {
        await _applyOp(client, op);
        await _stampAccount(op);
        await (_db.delete(_db.outbox)..where((o) => o.id.equals(op.id))).go();
        done++;
      } on GoogleApiException catch (e) {
        debugPrint(
          '[sync] push op failed entity=${op.entity} status=${e.status}',
        );
        await _handleOpError(op, e);
      }
    }
    return done;
  }

  /// Whether [op] may be pushed under the active account. Rows stamped
  /// with a different account belong to that account's loop. Legacy rows
  /// without a stamp keep the old single-account behavior (owned).
  Future<bool> _ownedByActiveAccount(OutboxData op) async {
    if (account == null) return true;
    if (op.entity == 'event_remote' || op.entity == 'task_remote') {
      final owner = _opPayload(op)['account'] as String?;
      return owner == null || owner == account;
    }
    if (op.entity == 'event') {
      final e = await (_db.select(
        _db.events,
      )..where((t) => t.id.equals(op.entityId))).getSingleOrNull();
      if (e == null) return true;
      return e.googleAccount == null || e.googleAccount == account;
    }
    if (op.entity == 'task') {
      final t = await (_db.select(
        _db.tasks,
      )..where((x) => x.id.equals(op.entityId))).getSingleOrNull();
      if (t == null) return true;
      return t.googleAccount == null || t.googleAccount == account;
    }
    if (op.entity == 'task_list') {
      final l = await (_db.select(
        _db.taskLists,
      )..where((x) => x.id.equals(op.entityId))).getSingleOrNull();
      if (l == null) return true;
      return l.googleAccount == null || l.googleAccount == account;
    }
    return true;
  }

  Future<void> _applyOp(GoogleApiClient client, OutboxData op) async {
    if (op.entity == 'event_remote') {
      final p = _opPayload(op);
      final calendarRemoteId = p['calendarRemoteId'] as String?;
      final eventRemoteId = p['eventRemoteId'] as String?;
      if (calendarRemoteId != null && eventRemoteId != null) {
        await client.eventDelete(calendarRemoteId, eventRemoteId);
      }
      return;
    }
    if (op.entity == 'task_remote') {
      final p = _opPayload(op);
      final listRemoteId = p['listRemoteId'] as String?;
      final taskRemoteId = p['taskRemoteId'] as String?;
      if (listRemoteId != null && taskRemoteId != null) {
        await client.taskDelete(listRemoteId, taskRemoteId);
      }
      return;
    }
    if (op.entity == 'event') {
      final e = await (_db.select(
        _db.events,
      )..where((t) => t.id.equals(op.entityId))).getSingleOrNull();
      // Deleted locally and purged: nothing to push.
      if (e == null) return;
      final calId = await _remoteCalendarId(e.calendarId) ?? e.calendarId;
      if (op.op == 'delete' || e.deletedAt != null) {
        if (e.remoteId != null) {
          await client.eventDelete(calId, e.remoteId!);
        }
        return;
      }
      if (op.op == 'move' && e.remoteId != null) {
        final p = _opPayload(op);
        final fromRemote =
            p['fromRemoteCalendarId'] as String? ??
            (p['fromCalendarId'] == null
                ? null
                : await _remoteCalendarId(p['fromCalendarId'] as String));
        final destinationRemote = await _remoteCalendarId(e.calendarId);
        if (fromRemote != null &&
            destinationRemote != null &&
            fromRemote != destinationRemote) {
          final moved = await client.eventMove(
            fromRemote,
            e.remoteId!,
            destinationRemote,
          );
          await (_db.update(_db.events)..where((t) => t.id.equals(e.id))).write(
            EventsCompanion(
              remoteId: Value(moved['id'] as String? ?? e.remoteId),
              remoteEtag: Value(moved['etag'] as String?),
              dirty: const Value(false),
            ),
          );
          return;
        }
      }
      if (e.remoteId == null) {
        final body = eventToGoogle(e);
        final atts = await (_db.select(
          _db.eventAttendees,
        )..where((a) => a.eventId.equals(e.id))).get();
        if (atts.isNotEmpty) {
          body['attendees'] = atts.map((a) => {'email': a.email}).toList();
        }
        final created = await client.eventInsert(calId, body);
        await (_db.update(_db.events)..where((t) => t.id.equals(e.id))).write(
          EventsCompanion(
            remoteId: Value(created['id'] as String?),
            remoteEtag: Value(created['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      } else {
        try {
          final body = eventToGoogle(e);
          final atts = await (_db.select(
            _db.eventAttendees,
          )..where((a) => a.eventId.equals(e.id))).get();
          if (atts.isNotEmpty) {
            body['attendees'] = atts.map((a) => {'email': a.email}).toList();
          }
          final updated = await client.eventPatch(
            calId,
            e.remoteId!,
            body,
            etag: e.remoteEtag,
          );
          await (_db.update(_db.events)..where((t) => t.id.equals(e.id))).write(
            EventsCompanion(
              remoteEtag: Value(updated['etag'] as String?),
              dirty: const Value(false),
            ),
          );
        } on GoogleApiException catch (err) {
          if (err.isConflict) {
            // Re-fetch series etag and re-apply intent, not blind overwrite.
            final page = await client.eventsList(
              calId,
              timeMin: _iso(_now() - 30 * msPerDay),
              timeMax: _iso(_now() + 90 * msPerDay),
            );
            final remote = page.items
                .where((m) => m['id'] == e.remoteId)
                .firstOrNull;
            if (remote == null) {
              final created = await client.eventInsert(calId, eventToGoogle(e));
              await (_db.update(
                _db.events,
              )..where((t) => t.id.equals(e.id))).write(
                EventsCompanion(
                  remoteId: Value(created['id'] as String?),
                  remoteEtag: Value(created['etag'] as String?),
                  dirty: const Value(false),
                ),
              );
            } else {
              final updated = await client.eventPatch(
                calId,
                e.remoteId!,
                eventToGoogle(e),
                etag: remote['etag'] as String?,
              );
              await (_db.update(
                _db.events,
              )..where((t) => t.id.equals(e.id))).write(
                EventsCompanion(
                  remoteEtag: Value(updated['etag'] as String?),
                  dirty: const Value(false),
                ),
              );
            }
          } else {
            rethrow;
          }
        }
      }
    } else if (op.entity == 'task') {
      final t = await (_db.select(
        _db.tasks,
      )..where((x) => x.id.equals(op.entityId))).getSingleOrNull();
      if (t == null) return;
      final listId = await _remoteTaskListId(t.listId) ?? '@default';
      if (op.op == 'delete' || t.deletedAt != null) {
        if (t.remoteId != null) {
          await client.taskDelete(listId, t.remoteId!);
        }
        return;
      }
      if (op.op == 'move' && t.remoteId != null) {
        final p = _opPayload(op);
        final fromRemote =
            p['fromRemoteListId'] as String? ??
            (p['fromListId'] == null
                ? null
                : await _remoteTaskListId(p['fromListId'] as String));
        final destinationRemote = await _remoteTaskListId(t.listId);
        if (fromRemote != null &&
            destinationRemote != null &&
            fromRemote != destinationRemote) {
          final moved = await client.taskMove(
            fromRemote,
            t.remoteId!,
            destinationRemote,
          );
          await (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(
            TasksCompanion(
              remoteId: Value(moved['id'] as String? ?? t.remoteId),
              remoteEtag: Value(moved['etag'] as String?),
              dirty: const Value(false),
            ),
          );
          return;
        }
      }
      if (t.remoteId == null) {
        final created = await client.taskInsert(listId, taskToGoogle(t));
        await (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(
          TasksCompanion(
            remoteId: Value(created['id'] as String?),
            remoteEtag: Value(created['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      } else {
        final updated = await client.taskPatch(
          listId,
          t.remoteId!,
          taskToGoogle(t),
          etag: t.remoteEtag,
        );
        await (_db.update(_db.tasks)..where((x) => x.id.equals(t.id))).write(
          TasksCompanion(
            remoteEtag: Value(updated['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      }
    } else if (op.entity == 'task_list') {
      final list = await (_db.select(
        _db.taskLists,
      )..where((l) => l.id.equals(op.entityId))).getSingleOrNull();
      if (list == null) return;
      if (op.op == 'delete' || list.deletedAt != null) {
        if (list.remoteId != null) {
          await client.taskListDelete(list.remoteId!);
        }
        await _hardDeleteTaskList(list.id);
        return;
      }
      if (list.remoteId == null) {
        final created = await client.taskListCreate(list.name);
        await (_db.update(
          _db.taskLists,
        )..where((l) => l.id.equals(list.id))).write(
          TaskListsCompanion(
            remoteId: Value(created['id'] as String?),
            remoteEtag: Value(created['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      } else {
        final updated = await client.taskListPatch(list.remoteId!, list.name);
        await (_db.update(
          _db.taskLists,
        )..where((l) => l.id.equals(list.id))).write(
          TaskListsCompanion(
            remoteEtag: Value(updated['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      }
    }
  }

  /// Removes a task list only after its remote delete succeeded. Detaches any
  /// remaining tasks (including trashed ones) so the foreign key stays valid.
  Future<void> _hardDeleteTaskList(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.listId.equals(id))).write(
      const TasksCompanion(listId: Value(null)),
    );
    await (_db.delete(_db.taskLists)..where((l) => l.id.equals(id))).go();
  }

  /// Records which account last pushed a row, so the next run pushes it
  /// under the same account instead of 404ing under another token.
  Future<void> _stampAccount(OutboxData op) async {
    if (account == null) return;
    if (op.entity == 'event') {
      await (_db.update(_db.events)..where((t) => t.id.equals(op.entityId)))
          .write(EventsCompanion(googleAccount: Value(account)));
    } else if (op.entity == 'task') {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(op.entityId)))
          .write(TasksCompanion(googleAccount: Value(account)));
    } else if (op.entity == 'task_list') {
      await (_db.update(_db.taskLists)..where((l) => l.id.equals(op.entityId)))
          .write(TaskListsCompanion(googleAccount: Value(account)));
    }
  }

  Future<void> _handleOpError(OutboxData op, GoogleApiException e) async {
    if (e.isPermissionDenied) {
      // Expired/revoked token or a grant missing the needed scope (for
      // example Calendar-only trying Tasks). The row is valid; keep it due
      // with backoff and surface it for the reconnect banner.
      _authFailure = true;
      debugPrint('[sync] auth failure on op ${op.id} status=${e.status}');
      await (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(
        OutboxCompanion(
          attempts: Value(op.attempts + 1),
          nextTryAt: Value(_now() + _backoffMs(op.attempts)),
          lastError: Value('auth ${e.status}: reconnect Google'),
        ),
      );
      return;
    }
    if (e.isRateLimited) {
      final wait = (e.retryAfterSec ?? 60) * 1000;
      await (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(
        OutboxCompanion(
          nextTryAt: Value(_now() + wait),
          lastError: Value('rate limited'),
          attempts: Value(op.attempts + 1),
        ),
      );
      return;
    }
    // 404 here means the remote row is genuinely gone: the op reached the
    // right account (wrong-account rows are skipped before any API call).
    if (e.status == 404) {
      debugPrint('[sync] dropping gone outbox op ${op.id} status=404');
      if (op.entity == 'task_list' && op.op == 'delete') {
        // The remote list is gone; clear the local tombstone so discovery
        // cannot revive it forever.
        await _hardDeleteTaskList(op.entityId);
      }
      await (_db.delete(_db.outbox)..where((o) => o.id.equals(op.id))).go();
      return;
    }
    if ([400, 409].contains(e.status) && op.attempts + 1 >= SyncEngine.maxAttempts) {
      await (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(
        OutboxCompanion(
          lastError: Value('failed: ${e.status}'),
          attempts: Value(op.attempts + 1),
        ),
      );
      return;
    }
    if (e.status >= 400 && e.status < 500) {
      await (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(
        OutboxCompanion(
          attempts: Value(op.attempts + 1),
          nextTryAt: Value(_now() + _backoffMs(op.attempts)),
          lastError: Value('failed: ${e.status}'),
        ),
      );
      return;
    }
    await (_db.update(_db.outbox)..where((o) => o.id.equals(op.id))).write(
      OutboxCompanion(
        attempts: Value(op.attempts + 1),
        nextTryAt: Value(_now() + _backoffMs(op.attempts)),
        lastError: Value('error ${e.status}'),
      ),
    );
  }
}
