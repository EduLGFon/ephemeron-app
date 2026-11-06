part of '../microsoft_sync_engine.dart';

extension on MicrosoftSyncEngine {
  Future<({int count, Map<String, String> idsByRemote})> _syncTaskLists(
    List<MsTodoList> todoLists,
    int now,
  ) async {
    final listIdByRemote = <String, String>{};
    var listCount = 0;
    for (final l in todoLists) {
      final remoteId = l.id;
      if (remoteId.isEmpty) continue;
      final existing =
          await (_db.select(_db.taskLists)..where(
                (t) =>
                    t.microsoftAccount.equals(account) &
                    t.remoteId.equals(remoteId),
              ))
              .getSingleOrNull();
      if (existing == null) {
        final id = 'mstl_${account}_$remoteId';
        await _db
            .into(_db.taskLists)
            .insert(
              TaskListsCompanion.insert(
                id: id,
                remoteId: Value(remoteId),
                name: l.displayName.isEmpty ? remoteId : l.displayName,
                color: const Value(null),
                microsoftAccount: Value(account),
                createdAt: now,
                updatedAt: now,
              ),
            );
        listIdByRemote[remoteId] = id;
        listCount++;
      } else {
        await (_db.update(
          _db.taskLists,
        )..where((t) => t.id.equals(existing.id))).write(
          TaskListsCompanion(
            name: Value(l.displayName.isEmpty ? existing.name : l.displayName),
            microsoftAccount: Value(account),
            dirty: const Value(false),
            updatedAt: Value(now),
          ),
        );
        listIdByRemote[remoteId] = existing.id;
      }
    }
    return (count: listCount, idsByRemote: listIdByRemote);
  }

  Future<int> _syncTasks(
    List<MsTodoList> todoLists,
    Map<String, String> listIdByRemote,
    int now,
  ) async {
    var taskCount = 0;
    for (final l in todoLists) {
      final remoteListId = l.id;
      if (remoteListId.isEmpty) continue;
      final localListId = listIdByRemote[remoteListId];
      if (localListId == null) continue;
      final tasks = await _client.listTodoTasks(remoteListId);
      final remoteTaskIds = {
        for (final t in tasks)
          if (t.id.isNotEmpty) t.id,
      };
      for (final t in tasks) {
        final remoteId = t.id;
        if (remoteId.isEmpty) continue;
        final existing =
            await (_db.select(_db.tasks)..where(
                  (x) =>
                      x.microsoftAccount.equals(account) &
                      x.remoteId.equals(remoteId),
                ))
                .getSingleOrNull();
        final dueUtc = t.dueDateTime?.utc;
        final dueDate = dueUtc != null ? _dateStr(dueUtc) : null;
        final dueTime = dueUtc != null
            ? dueUtc.hour * 60 + dueUtc.minute
            : null;
        final completedAt = (t.status == 'completed')
            ? t.completedDateTime?.utc?.millisecondsSinceEpoch
            : null;
        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        if (existing == null) {
          await _db
              .into(_db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: 'mstask_${account}_$remoteId',
                  listId: Value(localListId),
                  title: Value(t.title),
                  notes: Value(t.body),
                  dueDate: Value(dueDate),
                  dueTime: Value(dueTime),
                  completedAt: Value(completedAt),
                  microsoftAccount: Value(account),
                  remoteId: Value(remoteId),
                  dirty: const Value(false),
                  createdAt: nowMs,
                  updatedAt: nowMs,
                ),
              );
          taskCount++;
        } else {
          await (_db.update(
            _db.tasks,
          )..where((x) => x.id.equals(existing.id))).write(
            TasksCompanion(
              listId: Value(localListId),
              title: Value(t.title),
              notes: Value(t.body),
              dueDate: Value(dueDate),
              dueTime: Value(dueTime),
              completedAt: Value(completedAt),
              microsoftAccount: Value(account),
              remoteId: Value(remoteId),
              dirty: const Value(false),
              updatedAt: Value(nowMs),
              // Preserve local-only fields.
              plannedDate: Value(existing.plannedDate),
              plannedStart: Value(existing.plannedStart),
              plannedEnd: Value(existing.plannedEnd),
              seriesId: Value(existing.seriesId),
              recurrenceKey: Value(existing.recurrenceKey),
              priority: Value(existing.priority),
              durationMin: Value(existing.durationMin),
              rrule: Value(existing.rrule),
              repeatMode: Value(existing.repeatMode),
              pinned: Value(existing.pinned),
              wontDo: Value(existing.wontDo),
              alarmPreset: Value(existing.alarmPreset),
              reminders: Value(existing.reminders),
            ),
          );
          taskCount++;
        }
      }
      // Reconcile task deletions only after a complete, successful fetch for
      // this list. calendarView is time-windowed, so event deletion
      // reconciliation is not attempted (fail-safe).
      await _reconcileDeletedTasks(localListId, remoteTaskIds, now);
    }
    return taskCount;
  }

  Future<void> _reconcileDeletedTaskLists(
    Set<String> remoteListIds,
    int nowMs,
  ) async {
    final candidates =
        await (_db.select(_db.taskLists)..where(
              (t) =>
                  t.microsoftAccount.equals(account) &
                  t.remoteId.isNotNull() &
                  t.deletedAt.isNull() &
                  t.dirty.equals(false),
            ))
            .get();
    for (final list in candidates) {
      final remoteId = list.remoteId;
      if (remoteId == null || remoteId.isEmpty) continue;
      if (remoteListIds.contains(remoteId)) continue;
      // List disappeared from Graph; soft-delete list and its MS-synced tasks.
      await (_db.update(
        _db.taskLists,
      )..where((t) => t.id.equals(list.id))).write(
        TaskListsCompanion(
          deletedAt: Value(nowMs),
          updatedAt: Value(nowMs),
          dirty: const Value(false),
        ),
      );
      await (_db.update(_db.tasks)..where(
            (t) =>
                t.listId.equals(list.id) &
                t.microsoftAccount.equals(account) &
                t.remoteId.isNotNull() &
                t.deletedAt.isNull() &
                t.dirty.equals(false),
          ))
          .write(
            TasksCompanion(
              deletedAt: Value(nowMs),
              updatedAt: Value(nowMs),
              dirty: const Value(false),
            ),
          );
    }
  }

  Future<void> _reconcileDeletedTasks(
    String localListId,
    Set<String> remoteTaskIds,
    int nowMs,
  ) async {
    final candidates =
        await (_db.select(_db.tasks)..where(
              (t) =>
                  t.listId.equals(localListId) &
                  t.microsoftAccount.equals(account) &
                  t.remoteId.isNotNull() &
                  t.deletedAt.isNull() &
                  t.dirty.equals(false),
            ))
            .get();
    for (final task in candidates) {
      final remoteId = task.remoteId;
      if (remoteId == null || remoteId.isEmpty) continue;
      if (remoteTaskIds.contains(remoteId)) continue;
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          deletedAt: Value(nowMs),
          updatedAt: Value(nowMs),
          dirty: const Value(false),
        ),
      );
    }
  }
}
