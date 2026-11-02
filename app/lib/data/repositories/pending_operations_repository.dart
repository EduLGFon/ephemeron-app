// Durable buffer for destructive operations with a short undo window.
// UI treats pending entities as already gone; the real mutation runs when the
// timer expires or on next launch (whichever comes first).
import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';

class PendingOperationsRepository {
  PendingOperationsRepository(this._db);
  final AppDatabase _db;

  Future<String> enqueue({
    required String entity,
    required String entityId,
    required String op,
    String? payload,
    Duration delay = const Duration(seconds: 6),
  }) async {
    final id = newId();
    final now = nowMs();
    await _db
        .into(_db.pendingOperations)
        .insert(
          PendingOperationsCompanion.insert(
            id: id,
            entity: entity,
            entityId: entityId,
            op: op,
            payload: Value(payload),
            scheduledAt: now + delay.inMilliseconds,
            createdAt: now,
          ),
        );
    return id;
  }

  Future<void> cancel(String id) async {
    await (_db.delete(
      _db.pendingOperations,
    )..where((p) => p.id.equals(id))).go();
  }

  Future<void> cancelAll(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.delete(
      _db.pendingOperations,
    )..where((p) => p.id.isIn(list))).go();
  }

  Future<List<PendingOperation>> all() {
    return (_db.select(
      _db.pendingOperations,
    )..orderBy([(p) => OrderingTerm.asc(p.scheduledAt)])).get();
  }

  Future<List<PendingOperation>> dueNow() {
    return (_db.select(_db.pendingOperations)
          ..where((p) => p.scheduledAt.isSmallerOrEqualValue(nowMs()))
          ..orderBy([(p) => OrderingTerm.asc(p.scheduledAt)]))
        .get();
  }

  Future<PendingOperation?> next() {
    return (_db.select(_db.pendingOperations)
          ..orderBy([(p) => OrderingTerm.asc(p.scheduledAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> remove(String id) async {
    await (_db.delete(
      _db.pendingOperations,
    )..where((p) => p.id.equals(id))).go();
  }

  Stream<Set<String>> watchEntityIds(
    String entity, {
    Set<String> ops = const {},
  }) {
    final q = _db.selectOnly(_db.pendingOperations)
      ..addColumns([_db.pendingOperations.entityId])
      ..where(_db.pendingOperations.entity.equals(entity));
    if (ops.isNotEmpty) {
      q.where(_db.pendingOperations.op.isIn(ops));
    }
    return q.watch().map(
      (rows) =>
          rows.map((r) => r.read(_db.pendingOperations.entityId)!).toSet(),
    );
  }
}

/// Subquery selecting entity ids with a pending operation for [entity].
/// Use with `column.isNotInQuery(...)` to keep optimistic lists in sync.
JoinedSelectStatement pendingIdsQuery(
  AppDatabase db, {
  required String entity,
  Set<String> ops = const {},
}) {
  final q = db.selectOnly(db.pendingOperations)
    ..addColumns([db.pendingOperations.entityId])
    ..where(db.pendingOperations.entity.equals(entity));
  if (ops.isNotEmpty) {
    q.where(db.pendingOperations.op.isIn(ops));
  }
  return q;
}
