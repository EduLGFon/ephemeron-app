// Fake-server suite: 410 resets, etag conflicts, 429 backoff, offline
// queues, partial failure, idempotent resume.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/remote/google_api_client.dart';
import 'package:ephemeron/features/sync/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGoogle implements GoogleApiClient {
  List<Map<String, dynamic>> events = [];
  String? lastSyncTokenSeen;
  String? lastEtagSeen;
  bool fail410Once = false;
  bool fail429Once = false;
  bool fail412Once = false;
  int inserts = 0;
  int patches = 0;
  int? retryAfterSec;

  @override
  Future<List<Map<String, dynamic>>> calendarList() async => [];

  @override
  Future<CalendarPage> eventsList(
    String calendarId, {
    String? syncToken,
    String? timeMin,
    String? timeMax,
  }) async {
    if (fail410Once) {
      fail410Once = false;
      throw GoogleApiException(410, 'gone');
    }
    lastSyncTokenSeen = syncToken;
    return CalendarPage(items: List.of(events), nextSyncToken: 'tok123');
  }

  @override
  Future<Map<String, dynamic>> eventInsert(
    String calendarId,
    Map<String, dynamic> body,
  ) async {
    inserts++;
    return {'id': 'r$inserts', 'etag': 'e1'};
  }

  @override
  Future<Map<String, dynamic>> eventPatch(
    String calendarId,
    String eventId,
    Map<String, dynamic> body, {
    String? etag,
  }) async {
    lastEtagSeen = etag;
    if (fail412Once) {
      fail412Once = false;
      throw GoogleApiException(412, 'etag mismatch');
    }
    patches++;
    return {'etag': 'e$patches'};
  }

  @override
  Future<void> eventDelete(String c, String e) async {}

  @override
  Future<List<Map<String, dynamic>>> taskLists() async => [];

  @override
  Future<TasksPage> tasksList(String id, {String? updatedMin}) async =>
      TasksPage(items: [], nextUpdatedMin: 'now');

  @override
  Future<Map<String, dynamic>> taskInsert(
    String l,
    Map<String, dynamic> b,
  ) async => {'id': 't1', 'etag': 'e1'};

  @override
  Future<Map<String, dynamic>> taskPatch(
    String l,
    String t,
    Map<String, dynamic> b, {
    String? etag,
  }) async => {'etag': 'e2'};

  @override
  Future<void> taskDelete(String l, String t) async {}
}

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
  test('pull saves token, second pull sends it', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final fake = FakeGoogle()
      ..events = [
        {
          'id': 'g1',
          'etag': 'a',
          'summary': 'Meet',
          'status': 'confirmed',
          'start': {'dateTime': '2026-03-03T09:00:00Z'},
          'end': {'dateTime': '2026-03-03T10:00:00Z'},
        },
      ];
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    expect(engine.status, SyncStatus.synced);
    await engine.syncNow();
    expect(fake.lastSyncTokenSeen, 'tok123');
    // Idempotent: single row for the remote event.
    final rows = await db.select(db.events).get();
    expect(rows.where((e) => e.remoteId == 'g1'), hasLength(1));
  });

  test('410 clears synced rows but keeps dirty local rows', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'synced',
            calendarId: 'c1',
            remoteId: Value('g-old'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'dirty',
            calendarId: 'c1',
            createdAt: now,
            updatedAt: now,
            dirty: Value(true),
          ),
        );
    final fake = FakeGoogle()
      ..fail410Once = true
      ..events = [];
    // Seed a token so the 410 path triggers.
    await db
        .into(db.syncState)
        .insert(
          SyncStateCompanion.insert(
            key: 'cal:c1:token',
            value: Value('old-tok'),
          ),
        );
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    final rows = await db.select(db.events).get();
    expect(rows.map((e) => e.id), contains('dirty'));
    expect(rows.map((e) => e.id), isNot(contains('synced')));
  });

  test('push insert assigns remote id; patch sends etag', () async {
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
    final fake = FakeGoogle()
      ..events = [
        {'id': 'r1', 'etag': 'e1', 'summary': 'New', 'status': 'confirmed'},
      ];
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    expect(fake.inserts, 1);
    expect((await db.select(db.outbox).get()), isEmpty);
    final rows = await (db.select(
      db.events,
    )..where((t) => t.remoteId.equals('r1'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.dirty, isFalse);
  });

  test('412 conflict refetches and reapplies with new etag', () async {
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
            title: Value('Mine'),
            remoteId: Value('g1'),
            remoteEtag: Value('stale'),
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
            op: 'update',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle()
      ..fail412Once = true
      ..events = [
        {
          'id': 'g1',
          'etag': 'fresh',
          'summary': 'Theirs',
          'status': 'confirmed',
          'start': {'dateTime': '2026-03-03T09:00:00Z'},
          'end': {'dateTime': '2026-03-03T10:00:00Z'},
        },
      ];
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    // First attempt stale, retry with fresh etag.
    expect(fake.lastEtagSeen, 'fresh');
    expect((await db.select(db.outbox).get()), isEmpty);
  });

  test('429 sets nextTryAt; retryFailed resets', () async {
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
            remoteId: Value('g1'),
            remoteEtag: Value('e0'),
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
            op: 'update',
            createdAt: now,
          ),
        );
    final fake = _RateLimitedOnce();
    final engine = SyncEngine(db, clientFactory: () => fake);
    await engine.syncNow();
    final op = await (db.select(
      db.outbox,
    )..where((o) => o.id.equals('op1'))).getSingle();
    expect(op.nextTryAt, isNotNull);
    await engine.retryFailed('op1');
    final reset = await (db.select(
      db.outbox,
    )..where((o) => o.id.equals('op1'))).getSingle();
    expect(reset.nextTryAt, isNull);
    expect(reset.attempts, 0);
  });

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
}

class _RateLimitedOnce extends FakeGoogle {
  @override
  Future<Map<String, dynamic>> eventPatch(
    String calendarId,
    String eventId,
    Map<String, dynamic> body, {
    String? etag,
  }) async {
    throw GoogleApiException(429, 'slow down', retryAfterSec: 5);
  }
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
