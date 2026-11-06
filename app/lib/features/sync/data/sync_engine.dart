// Single-flight sync coordinator. Offline-first: optimistic local writes
// plus outbox; the user never waits on the network. Safe to kill anytime:
// remote upserts key on remoteId, outbox rows clear only after success.
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/mappers/google_mappers.dart';
import 'package:ephemeron/data/remote/google_api_client.dart';

part 'sync_engine/push.dart';
part 'sync_engine/push_apply.dart';
part 'sync_engine/push_error.dart';
part 'sync_engine/pull.dart';

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
  bool _authFailure = false;

  /// Set when any op in the last run failed with an auth/permission error.
  /// Drives the reconnect banner; reset on every [syncNow].
  bool get authFailure => _authFailure;

  /// Cross-instance single-flight: the notifier, auto-sync timer, sign-in
  /// flow and headless worker each build their own engine.
  static bool _busy = false;
  final _rand = Random();

  /// Remote calendar/task-list ids seen for the active account in this run.
  /// Pull skips null-stamped rows that are absent here: they belong to an
  /// account that is not signed in (or a deleted remote), and querying them
  /// under this token only produces 404 noise.
  Set<String>? _accountCalendarIds;
  Set<String>? _accountListIds;

  SyncStatus get status => _status;
  String? get lastError => _lastError;

  static const int maxAttempts = 5;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// Runs push then pull. Concurrent calls collapse into one run.
  Future<void> syncNow() async {
    if (_running || _busy) {
      debugPrint('[sync] syncNow skipped: already running');
      return;
    }
    _running = true;
    _busy = true;
    _status = SyncStatus.syncing;
    _authFailure = false;
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
      if (_authFailure) {
        // Push or pull hit an auth/permission error (expired token, revoked
        // access, missing Tasks scope with a Calendar-only grant). The rows
        // are kept; the user must reconnect. Never report clean success.
        _status = SyncStatus.error;
        _lastError = 'Google auth';
        debugPrint('[sync] syncNow finished with auth failures');
      } else {
        _status = SyncStatus.synced;
        _lastError = null;
        debugPrint('[sync] syncNow ok');
      }
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
      _busy = false;
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

  int _backoffMs(int attempts) {
    final base = 5000 * (1 << attempts.clamp(0, 5));
    return base + _rand.nextInt(1000);
  }

  static bool _isGoogleEntity(String entity) =>
      entity == 'event' ||
      entity == 'task' ||
      entity == 'task_list' ||
      entity == 'event_remote' ||
      entity == 'task_remote';

  Map<String, dynamic> _opPayload(OutboxData op) {
    final raw = op.payload;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
}
