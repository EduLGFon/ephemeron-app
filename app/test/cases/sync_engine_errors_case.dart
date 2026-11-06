// Fake-server suite (errors): offline queues, partial failure, auth/permission/rate-limit/404.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/remote/google_api_client.dart';
import 'package:ephemeron/features/sync/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_engine_case.dart' show FakeGoogle;

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<String> _cal(AppDatabase db, {String source = 'google'}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: 'c1',
          remoteId: Value('cal-remote'),
          name: 'c',
          source: Value(source),
          createdAt: now,
          updatedAt: now,
        ),
      );
  return 'c1';
}

void main() {
  test('offline keeps queue and reports offline', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op1',
            entity: 'event',
            entityId: 'x',
            op: 'create',
            createdAt: now,
          ),
        );
    final engine = SyncEngine(db, clientFactory: () => null);
    await engine.syncNow();
    expect(engine.status, SyncStatus.offline);
    expect(await engine.pendingCount(), 1);
  });

  test('partial failure lets other ops proceed', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final id in ['ok', 'bad']) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: id,
              calendarId: 'c1',
              title: Value(id),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'op-$id',
              entity: 'event',
              entityId: id,
              op: 'create',
              createdAt: now,
            ),
          );
    }
    final fake = _PartialFail();
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    final remaining = await db.select(db.outbox).get();
    expect(remaining.map((o) => o.id), ['op-bad']);
  });

  test('401 push keeps the row and reports auth failure', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'e1',
            calendarId: 'c1',
            title: Value('New'),
            createdAt: now,
            updatedAt: now,
            dirty: Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op1',
            entity: 'event',
            entityId: 'e1',
            op: 'create',
            createdAt: now,
          ),
        );
    final engine = SyncEngine(
      db,
      clientFactory: () => _FailAll(401, 'no token'),
    );
    await engine.syncNow();
    // Row kept for retry, engine signals reconnect instead of clean success.
    final op = await (db.select(
      db.outbox,
    )..where((o) => o.id.equals('op1'))).getSingle();
    expect(op.attempts, 1);
    expect(op.nextTryAt, isNotNull);
    expect(engine.authFailure, isTrue);
    expect(engine.status, SyncStatus.error);
  });

  test('permission 403 keeps the row; rate-limit 403 backs off', () async {
    for (final body in [
      '{"error":{"errors":[{"reason":"insufficientPermissions"}],"code":403}}',
      '{"error":{"errors":[{"reason":"rateLimitExceeded"}],"code":403}}',
    ]) {
      final db = _db();
      addTearDown(db.close);
      await _cal(db);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'e1',
              calendarId: 'c1',
              title: Value('New'),
              createdAt: now,
              updatedAt: now,
              dirty: Value(true),
            ),
          );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'op1',
              entity: 'event',
              entityId: 'e1',
              op: 'create',
              createdAt: now,
            ),
          );
      final engine = SyncEngine(db, clientFactory: () => _FailAll(403, body));
      await engine.syncNow();
      final remaining = await (db.select(
        db.outbox,
      )..where((o) => o.id.equals('op1'))).get();
      // Neither flavor deletes the row anymore.
      expect(remaining, hasLength(1));
      if (body.contains('rateLimit')) {
        expect(engine.authFailure, isFalse);
        expect(remaining.single.lastError, 'rate limited');
      } else {
        expect(engine.authFailure, isTrue);
        expect(engine.status, SyncStatus.error);
      }
    }
  });

  test('404 drops owned rows but keeps foreign-account rows', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final entry in [('mine', 'a@x'), ('theirs', 'b@x')]) {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: entry.$1,
              calendarId: 'c1',
              title: Value(entry.$1),
              createdAt: now,
              updatedAt: now,
              dirty: Value(true),
              googleAccount: Value(entry.$2),
            ),
          );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              id: 'op-${entry.$1}',
              entity: 'event',
              entityId: entry.$1,
              op: 'create',
              createdAt: now,
            ),
          );
    }
    // Active account a@x: its own 404 is gone-remote (dropped); b@x rows
    // are skipped before any API call, so they survive.
    final engine = SyncEngine(
      db,
      clientFactory: () => _FailAll(404, 'not found'),
      account: 'a@x',
    );
    await engine.syncNow();
    final remaining = await db.select(db.outbox).get();
    expect(remaining.map((o) => o.id), ['op-theirs']);
  });
}

class _PartialFail extends FakeGoogle {
  @override
  Future<Map<String, dynamic>> eventInsert(
    String calendarId,
    Map<String, dynamic> body,
  ) async {
    if ((body['summary'] as String?) == 'bad') {
      throw GoogleApiException(500, 'boom');
    }
    return {'id': 'r-ok', 'etag': 'e1'};
  }
}

class _FailAll extends FakeGoogle {
  _FailAll(this.status, this.message);

  final int status;
  final String message;

  @override
  Future<List<Map<String, dynamic>>> calendarList() async =>
      throw GoogleApiException(status, message);

  @override
  Future<CalendarPage> eventsList(
    String calendarId, {
    String? syncToken,
    String? timeMin,
    String? timeMax,
  }) async => throw GoogleApiException(status, message);

  @override
  Future<Map<String, dynamic>> eventInsert(
    String calendarId,
    Map<String, dynamic> body,
  ) async => throw GoogleApiException(status, message);

  @override
  Future<List<Map<String, dynamic>>> taskLists() async =>
      throw GoogleApiException(status, message);

  @override
  Future<TasksPage> tasksList(String id, {String? updatedMin}) async =>
      throw GoogleApiException(status, message);
}
