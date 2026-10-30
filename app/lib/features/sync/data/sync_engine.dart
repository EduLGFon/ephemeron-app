// Single-flight sync coordinator. Offline-first: optimistic local writes
// plus outbox; the user never waits on the network. Safe to kill anytime:
// remote upserts key on remoteId, outbox rows clear only after success.
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/mappers/google_mappers.dart';
import 'package:ephemeron/data/remote/google_api_client.dart';

enum SyncStatus { synced, syncing, offline, error }

class SyncEngine {
  SyncEngine(
    this._db, {
    GoogleApiClient? Function()? clientFactory,
    this.account,
  }) : _clientFactory = clientFactory;

  final AppDatabase _db;
  final GoogleApiClient? Function()? _clientFactory;
  String? account;
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
    if (_running) {
      debugPrint('[sync] syncNow skipped: already running');
      return;
    }
    _running = true;
    _status = SyncStatus.syncing;
    debugPrint('[sync] syncNow start');
    try {
      final client = _clientFactory?.call();
      if (client == null) {
        debugPrint('[sync] no client (no token): offline');
        _status = SyncStatus.offline;
        return;
      }
      final pushed = await _pushOutbox(client);
      debugPrint('[sync] push done ops=$pushed');
      final cals = await _syncCalendarList(client);
      debugPrint(
        '[sync] calendar discovery done remote=${cals.$1} new=${cals.$2}',
      );
      final lists = await _syncTaskLists(client);
      debugPrint(
        '[sync] task-list discovery done remote=${lists.$1} new=${lists.$2}',
      );
      final events = await _pullCalendars(client);
      debugPrint('[sync] calendar pull done events=$events');
      final tasks = await _pullTasks(client);
      debugPrint('[sync] tasks pull done tasks=$tasks');
      _status = SyncStatus.synced;
      _lastError = null;
      debugPrint('[sync] syncNow ok');
    } on GoogleApiException catch (e) {
      debugPrint('[sync] GoogleApiException status=${e.status}');
      _status = SyncStatus.error;
      _lastError = 'Google ${e.status}';
    } catch (e) {
      debugPrint('[sync] unexpected error: $e');
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
      if (!_isGoogleEntity(op.entity)) continue;
      try {
        await _applyOp(client, op);
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
    // Stale rows from a previous account (or deleted remote) can never
    // succeed against the new account; drop them instead of retrying.
    if (e.status == 403 || e.status == 404) {
      debugPrint('[sync] dropping stale outbox op ${op.id} status=${e.status}');
      await (_db.delete(_db.outbox)..where((o) => o.id.equals(op.id))).go();
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

  static bool _isGoogleEntity(String entity) =>
      entity == 'event' || entity == 'task' || entity == 'task_list';

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

  // Discovery: mirror the remote calendar/task-list catalog locally so
  // the first sync after sign-in has something to pull into. Local-only
  // rows are never touched; renamed remotes update in place when clean.

  Future<(int, int)> _syncCalendarList(GoogleApiClient client) async {
    final remote = await client.calendarList();
    debugPrint('[sync] calendarList returned ${remote.length} items');
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
            CalendarsCompanion(remoteId: Value(id), updatedAt: Value(now)),
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
                source: const Value('google'),
                googleAccount: Value(account),
                readOnly: Value((c['accessRole'] as String?) == 'reader'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else if (!existing.dirty && name != null && name.isNotEmpty) {
        await (_db.update(
          _db.calendars,
        )..where((t) => t.id.equals(existing!.id))).write(
          CalendarsCompanion(name: Value(name), updatedAt: Value(now)),
        );
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
    // Disable calendars from accounts that are no longer reachable, but only
    // when the remote list is non-empty (an empty result is ambiguous).
    if (remote.isNotEmpty) {
      final remoteIds = {for (final c in remote) c['id'] as String?}
        ..removeWhere((x) => x == null);
      for (final c in all) {
        if (c.remoteId != null && !remoteIds.contains(c.remoteId)) {
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
    final now = _now();
    var created = 0;
    for (final l in remote) {
      final id = l['id'] as String?;
      if (id == null) continue;
      final name = (l['title'] as String?)?.trim();
      final existing = await (_db.select(
        _db.taskLists,
      )..where((t) => t.remoteId.equals(id))).getSingleOrNull();
      if (existing == null) {
        await _db
            .into(_db.taskLists)
            .insert(
              TaskListsCompanion.insert(
                id: newId(),
                remoteId: Value(id),
                name: (name == null || name.isEmpty) ? id : name,
                createdAt: now,
                updatedAt: now,
              ),
            );
        created++;
      } else if (!existing.dirty && name != null && name.isNotEmpty) {
        await (_db.update(
          _db.taskLists,
        )..where((t) => t.id.equals(existing.id))).write(
          TaskListsCompanion(name: Value(name), updatedAt: Value(now)),
        );
      }
    }
    return (remote.length, created);
  }

  // Pull.

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
        if (e.isGone) {
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

  Future<int> _fullCalendarResync(
    Calendar cal,
    GoogleApiClient client, {
    required bool keepDirty,
  }) async {
    final page = await client.eventsList(
      cal.remoteId ?? cal.id,
      timeMin: _iso(_now() - 30 * 86400000),
      timeMax: _iso(_now() + 90 * 86400000),
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
        await _db.into(_db.events).insert(mapped.companion);
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
    await _db.transaction(() async {
      await (_db.delete(
        _db.eventAttendees,
      )..where((a) => a.eventId.equals(eventId))).go();
      for (final a in atts) {
        final m = a as Map<String, dynamic>;
        final email = m['email'] as String?;
        if (email == null || email.isEmpty) continue;
        await _db
            .into(_db.eventAttendees)
            .insert(
              EventAttendeesCompanion.insert(
                id: newId(),
                eventId: eventId,
                email: email,
                rsvp: Value(m['responseStatus'] as String?),
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
      final updatedMin = await _syncValue('tasks:${list.id}:updatedMin');
      try {
        final page = await client.tasksList(remoteId, updatedMin: updatedMin);
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
      } on GoogleApiException catch (e) {
        debugPrint('[sync] tasks pull failed status=${e.status}');
        await _setSyncMeta('tasks:${list.id}', error: 'Google ${e.status}');
      }
    }
    return total;
  }

  Future<bool> _mergeTask(TaskList list, Map<String, dynamic> g) async {
    final remoteId = g['id'] as String?;
    if (remoteId == null) return false;
    final existing = await (_db.select(
      _db.tasks,
    )..where((t) => t.remoteId.equals(remoteId))).getSingleOrNull();
    if (existing == null) {
      final mapped = taskFromGoogle(g, list.id, newId());
      await _db.into(_db.tasks).insert(mapped.companion);
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

  String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
}
