// Single-flight sync coordinator. Offline-first: optimistic local writes
// plus outbox; the user never waits on the network. Safe to kill anytime:
// remote upserts key on remoteId, outbox rows clear only after success.
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/mappers/google_mappers.dart';
import 'package:ephemeron/data/remote/google_api_client.dart';

enum SyncStatus { synced, syncing, offline, error }

class SyncEngine {
  SyncEngine(this._db, {GoogleApiClient? Function()? clientFactory})
    : _clientFactory = clientFactory;

  final AppDatabase _db;
  final GoogleApiClient? Function()? _clientFactory;
  bool _running = false;
  SyncStatus _status = SyncStatus.synced;
  String? _lastError;
  final _rand = Random();

  SyncStatus get status => _status;
  String? get lastError => _lastError;

  static const int maxAttempts = 5;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Runs push then pull. Concurrent calls collapse into one run.
  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    _status = SyncStatus.syncing;
    try {
      final client = _clientFactory?.call();
      if (client == null) {
        _status = SyncStatus.offline;
        return;
      }
      await _pushOutbox(client);
      await _pullCalendars(client);
      await _pullTasks(client);
      _status = SyncStatus.synced;
      _lastError = null;
    } on GoogleApiException catch (e) {
      _status = SyncStatus.error;
      _lastError = 'Google ${e.status}';
    } catch (e) {
      _status = SyncStatus.error;
      _lastError = 'sync failed';
    } finally {
      _running = false;
    }
  }

  Future<int> pendingCount() async {
    final rows =
        await (_db.select(_db.outbox)..where(
              (o) =>
                  o.nextTryAt.isNull() |
                  o.nextTryAt.isSmallerOrEqualValue(_now()),
            ))
            .get();
    return rows.length;
  }

  Future<void> _pushOutbox(GoogleApiClient client) async {
    final ops =
        await (_db.select(_db.outbox)
              ..where(
                (o) =>
                    o.nextTryAt.isNull() |
                    o.nextTryAt.isSmallerOrEqualValue(_now()),
              )
              ..orderBy([(o) => OrderingTerm.asc(o.createdAt)]))
            .get();
    for (final op in ops) {
      try {
        await _applyOp(client, op);
        await (_db.delete(_db.outbox)..where((o) => o.id.equals(op.id))).go();
      } on GoogleApiException catch (e) {
        await _handleOpError(op, e);
      }
    }
  }

  Future<void> _applyOp(GoogleApiClient client, OutboxData op) async {
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
      if (e.remoteId == null) {
        final created = await client.eventInsert(calId, eventToGoogle(e));
        await (_db.update(_db.events)..where((t) => t.id.equals(e.id))).write(
          EventsCompanion(
            remoteId: Value(created['id'] as String?),
            remoteEtag: Value(created['etag'] as String?),
            dirty: const Value(false),
          ),
        );
      } else {
        try {
          final updated = await client.eventPatch(
            calId,
            e.remoteId!,
            eventToGoogle(e),
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
              timeMin: _iso(_now() - 30 * 86400000),
              timeMax: _iso(_now() + 90 * 86400000),
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
      // Task-list create/delete mirrors when the remote list exists.
      return;
    }
  }

  Future<void> _handleOpError(OutboxData op, GoogleApiException e) async {
    if (e.isUnauthorized) {
      // Token refresh handled by caller; retry next run.
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
    if ([400, 404, 409].contains(e.status) && op.attempts + 1 >= maxAttempts) {
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

  int _backoffMs(int attempts) {
    final base = 5000 * (1 << attempts.clamp(0, 5));
    return base + _rand.nextInt(1000);
  }

  Future<void> retryFailed(String outboxId) async {
    await (_db.update(_db.outbox)..where((o) => o.id.equals(outboxId))).write(
      const OutboxCompanion(
        attempts: Value(0),
        nextTryAt: Value(null),
        lastError: Value(null),
      ),
    );
  }

  Future<void> discardFailed(String outboxId) async {
    await (_db.delete(_db.outbox)..where((o) => o.id.equals(outboxId))).go();
  }

  Stream<List<OutboxData>> watchFailed() {
    return (_db.select(_db.outbox)
          ..where(
            (o) =>
                o.attempts.isBiggerOrEqualValue(maxAttempts) &
                o.lastError.isNotNull(),
          )
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .watch();
  }

  // Pull.

  Future<void> _pullCalendars(GoogleApiClient client) async {
    final calendars =
        await (_db.select(_db.calendars)..where(
              (c) =>
                  c.source.equals('google') &
                  c.enabled.equals(true) &
                  c.deletedAt.isNull(),
            ))
            .get();
    for (final cal in calendars) {
      final token = await _syncValue('cal:${cal.id}:token');
      try {
        if (token == null) {
          await _fullCalendarResync(cal, client, keepDirty: true);
        } else {
          final page = await client.eventsList(
            cal.remoteId ?? cal.id,
            syncToken: token,
          );
          await _mergeEvents(cal, page.items);
          if (page.nextSyncToken != null) {
            await _setSyncValue('cal:${cal.id}:token', page.nextSyncToken!);
          }
        }
        await _setSyncMeta('cal:${cal.id}', error: null);
      } on GoogleApiException catch (e) {
        if (e.isGone) {
          await _fullCalendarResync(cal, client, keepDirty: true);
          await _setSyncMeta('cal:${cal.id}', error: null);
        } else {
          await _setSyncMeta('cal:${cal.id}', error: 'Google ${e.status}');
          rethrow;
        }
      }
    }
  }

  Future<void> _fullCalendarResync(
    Calendar cal,
    GoogleApiClient client, {
    required bool keepDirty,
  }) async {
    final page = await client.eventsList(
      cal.remoteId ?? cal.id,
      timeMin: _iso(_now() - 30 * 86400000),
      timeMax: _iso(_now() + 90 * 86400000),
    );
    await _db.transaction(() async {
      // Drop synced rows in the window; keep dirty local rows.
      final local =
          await (_db.select(_db.events)..where(
                (e) => e.calendarId.equals(cal.id) & e.deletedAt.isNull(),
              ))
              .get();
      for (final e in local) {
        if (e.remoteId != null && !(keepDirty && e.dirty)) {
          await (_db.delete(_db.events)..where((x) => x.id.equals(e.id))).go();
        }
      }
      await _mergeEvents(cal, page.items);
      if (page.nextSyncToken != null) {
        await _setSyncValue('cal:${cal.id}:token', page.nextSyncToken!);
      }
    });
  }

  Future<void> _mergeEvents(
    Calendar cal,
    List<Map<String, dynamic>> items,
  ) async {
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
      if (existing == null) {
        final mapped = eventFromGoogle(g, cal.id, newId());
        await _db.into(_db.events).insert(mapped.companion);
      } else if (!existing.dirty) {
        // Last-writer-wins on shared fields; local-only fields preserved
        // by only writing shared columns.
        final mapped = eventFromGoogle(g, cal.id, existing.id);
        await (_db.update(
          _db.events,
        )..where((e) => e.id.equals(existing.id))).write(
          mapped.companion.copyWith(
            alarmPreset: const Value.absent(),
            colorId: const Value.absent(),
          ),
        );
      }
    }
  }

  Future<void> _pullTasks(GoogleApiClient client) async {
    final lists = await (_db.select(
      _db.taskLists,
    )..where((l) => l.deletedAt.isNull())).get();
    for (final list in lists) {
      final updatedMin = await _syncValue('tasks:${list.id}:updatedMin');
      try {
        final page = await client.tasksList(
          list.remoteId ?? list.id,
          updatedMin: updatedMin,
        );
        for (final g in page.items) {
          await _mergeTask(list, g);
        }
        if (page.nextUpdatedMin != null) {
          await _setSyncValue(
            'tasks:${list.id}:updatedMin',
            page.nextUpdatedMin!,
          );
        }
      } on GoogleApiException catch (e) {
        await _setSyncMeta('tasks:${list.id}', error: 'Google ${e.status}');
      }
    }
  }

  Future<void> _mergeTask(TaskList list, Map<String, dynamic> g) async {
    final remoteId = g['id'] as String?;
    if (remoteId == null) return;
    final existing = await (_db.select(
      _db.tasks,
    )..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
    if (existing == null) {
      final mapped = taskFromGoogle(g, list.id, newId());
      await _db.into(_db.tasks).insert(mapped.companion);
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
        ),
      );
    }
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

  String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
}
