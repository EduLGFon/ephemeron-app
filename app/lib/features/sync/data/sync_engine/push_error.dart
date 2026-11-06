part of '../sync_engine.dart';

extension on SyncEngine {
  /// Removes a task list only after its remote delete succeeded. Detaches any
  /// remaining tasks (including trashed ones) so the foreign key stays valid.
  Future<void> _hardDeleteTaskList(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.listId.equals(id))).write(
      const TasksCompanion(listId: Value(null)),
    );
    await (_db.delete(_db.taskLists)..where((l) => l.id.equals(id))).go();
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
    if ([400, 409].contains(e.status) &&
        op.attempts + 1 >= SyncEngine.maxAttempts) {
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
