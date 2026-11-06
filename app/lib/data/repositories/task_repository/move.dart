part of '../task_repository.dart';

mixin _TaskMoveOps on _TaskRepositoryBase {
  /// Moves tasks to [listId]; returns previous list ids for undo.
  ///
  /// Same-account Google lists use the Tasks API move endpoint. A move to
  /// another account, to a local list, or from a local list becomes a local
  /// copy plus a queued delete of the old remote row. A null [listId] moves
  /// the tasks to the local unlisted bucket.
  Future<Map<String, String?>> moveTasks(
    List<String> ids,
    String? listId,
  ) async {
    final target = listId == null ? null : await _list(listId);
    if (listId != null && (target == null || target.deletedAt != null)) {
      throw SourceMoveException('Task list not found.');
    }
    final targetAccount = target?.googleAccount;
    final targetRemoteList = target?.remoteId;
    final targetIsGoogle = targetRemoteList != null;
    final prev = <String, String?>{};

    await _db.transaction(() async {
      for (final id in ids) {
        final task = await (_db.select(
          _db.tasks,
        )..where((t) => t.id.equals(id))).getSingle();
        prev[id] = task.listId;
        if (task.listId == listId) continue;
        final source = task.listId == null ? null : await _list(task.listId!);
        final sourceAccount = task.googleAccount ?? source?.googleAccount;
        final sourceRemoteList = source?.remoteId;
        final sourceRemoteId = task.remoteId;
        final wasDirty = task.dirty;
        // Preserve the first source when a move is still queued.
        var remoteFrom = sourceRemoteList;
        final pendingMove =
            await (_db.select(_db.outbox)..where(
                  (o) =>
                      o.entity.equals('task') &
                      o.entityId.equals(id) &
                      o.op.equals('move'),
                ))
                .getSingleOrNull();
        if (pendingMove?.payload != null) {
          try {
            final p = jsonDecode(pendingMove!.payload!) as Map<String, dynamic>;
            remoteFrom = (p['fromRemoteListId'] as String?) ?? remoteFrom;
          } catch (_) {
            // Keep the current list as the source.
          }
        }
        final useRemoteMove =
            sourceAccount == targetAccount &&
            targetRemoteList != null &&
            remoteFrom != null &&
            sourceRemoteId != null;
        final now = nowMs();
        await (_db.delete(
          _db.outbox,
        )..where((o) => o.entity.equals('task') & o.entityId.equals(id))).go();
        if (useRemoteMove) {
          await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
            TasksCompanion(
              listId: Value(listId),
              googleAccount: Value(targetAccount),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
          await _enqueue(
            'task',
            id,
            'move',
            payload: jsonEncode({
              'fromListId': task.listId,
              'fromRemoteListId': remoteFrom,
            }),
          );
          if (wasDirty) await _enqueue('task', id, 'update');
          continue;
        }

        await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            listId: Value(listId),
            googleAccount: Value(targetAccount),
            remoteId: const Value(null),
            remoteEtag: const Value(null),
            updatedAt: Value(now),
            dirty: Value(targetIsGoogle),
          ),
        );
        if (targetIsGoogle) {
          await _enqueue('task', id, 'update');
        }
        if (remoteFrom != null &&
            sourceRemoteId != null &&
            sourceAccount != null) {
          await _enqueueRemoteDelete(
            taskId: id,
            listRemoteId: remoteFrom,
            taskRemoteId: sourceRemoteId,
            account: sourceAccount,
          );
        }
      }
    });
    return prev;
  }
}
