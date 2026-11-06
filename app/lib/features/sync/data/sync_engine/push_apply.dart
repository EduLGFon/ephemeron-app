part of '../sync_engine.dart';

extension on SyncEngine {
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
}
