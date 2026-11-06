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
}
