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
  List<Map<String, dynamic>> calendars = [];
  List<Map<String, dynamic>> taskListsResult = [];
  final List<String> pulledCalendars = [];
  final List<String> pulledTaskLists = [];
  String? lastSyncTokenSeen;
  String? lastEtagSeen;
  bool fail410Once = false;
  bool fail429Once = false;
  bool fail412Once = false;
  int inserts = 0;
  int patches = 0;
  int eventMoves = 0;
  int taskMoves = 0;
  int taskListCreates = 0;
  int taskListPatches = 0;
  String? lastTaskListTitle;
  final List<String> patchedTaskLists = [];
  final List<String> deletedTaskLists = [];
  final List<String> deletedEvents = [];
  final List<String> deletedTasks = [];
  int? retryAfterSec;

  @override
  Future<List<Map<String, dynamic>>> calendarList() async => List.of(calendars);

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
    pulledCalendars.add(calendarId);
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
  Future<Map<String, dynamic>> eventMove(
    String sourceCalendarId,
    String eventId,
    String destinationCalendarId,
  ) async {
    eventMoves++;
    return {'id': eventId, 'etag': 'moved$eventMoves'};
  }

  @override
  Future<void> eventDelete(String c, String e) async {
    deletedEvents.add(e);
  }

  @override
  Future<List<Map<String, dynamic>>> taskLists() async =>
      List.of(taskListsResult);

  @override
  Future<Map<String, dynamic>> taskListCreate(String title) async {
    taskListCreates++;
    lastTaskListTitle = title;
    return {
      'id': 'rl-new-$taskListCreates',
      'etag': 'list-etag-$taskListCreates',
    };
  }

  @override
  Future<Map<String, dynamic>> taskListPatch(
    String listId,
    String title,
  ) async {
    taskListPatches++;
    lastTaskListTitle = title;
    patchedTaskLists.add(listId);
    return {'id': listId, 'etag': 'list-etag-p$taskListPatches'};
  }

  @override
  Future<void> taskListDelete(String listId) async {
    deletedTaskLists.add(listId);
  }

  @override
  Future<TasksPage> tasksList(String id, {String? updatedMin}) async {
    pulledTaskLists.add(id);
    return TasksPage(items: [], nextUpdatedMin: 'now');
  }

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
  Future<Map<String, dynamic>> taskMove(
    String sourceTaskListId,
    String taskId,
    String destinationTaskListId,
  ) async {
    taskMoves++;
    return {'id': taskId, 'etag': 'task-moved$taskMoves'};
  }

  @override
  Future<void> taskDelete(String l, String t) async {
    deletedTasks.add(t);
  }
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

  test('discovery stamps accounts and disables only own calendars', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final entry in [('ca', 'ra'), ('cb', 'rb')]) {
      await db
          .into(db.calendars)
          .insert(
            CalendarsCompanion.insert(
              id: entry.$1,
              remoteId: Value(entry.$2),
              name: entry.$1,
              source: Value('google'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.taskLists)
          .insert(
            TaskListsCompanion.insert(
              id: 'l-${entry.$1}',
              remoteId: Value('rl-${entry.$2}'),
              name: 'l-${entry.$1}',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final fake = FakeGoogle()
      ..calendars = [
        {'id': 'ra', 'summary': 'ca'},
      ]
      ..taskListsResult = [
        {'id': 'rl-ra', 'title': 'l-ca'},
      ];
    final engine = SyncEngine(db, clientFactory: () => fake, account: 'a@x');
    await engine.syncNow();
    // Matched rows stamped; unmatched rows keep a null stamp.
    final ca = await (db.select(
      db.calendars,
    )..where((c) => c.id.equals('ca'))).getSingle();
    expect(ca.googleAccount, 'a@x');
    final cb = await (db.select(
      db.calendars,
    )..where((c) => c.id.equals('cb'))).getSingle();
    expect(cb.googleAccount, isNull);
    // rb belongs to another account: not disabled by a@x's loop.
    expect(cb.enabled, isTrue);
    final la = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals('l-ca'))).getSingle();
    expect(la.googleAccount, 'a@x');
    // Pull only queried the owned calendar/list: no foreign 404s.
    expect(fake.pulledCalendars, ['ra']);
    expect(fake.pulledTaskLists, ['rl-ra']);
  });

  test('event move uses move endpoint and clears dirty', () async {
    final db = _db();
    addTearDown(db.close);
    await _cal(db);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.calendars)
        .insert(
          CalendarsCompanion.insert(
            id: 'c2',
            remoteId: const Value('cal-remote-2'),
            name: 'Two',
            source: const Value('google'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'e1',
            calendarId: 'c2',
            title: const Value('Moved'),
            remoteId: const Value('g1'),
            remoteEtag: const Value('old'),
            googleAccount: const Value('a@x'),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-move',
            entity: 'event',
            entityId: 'e1',
            op: 'move',
            payload: const Value(
              '{"fromCalendarId":"c1","fromRemoteCalendarId":"cal-remote"}',
            ),
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake, account: 'a@x');

    await engine.syncNow();

    expect(fake.eventMoves, 1);
    final event = await (db.select(
      db.events,
    )..where((e) => e.id.equals('e1'))).getSingle();
    expect(event.remoteId, 'g1');
    expect(event.remoteEtag, 'moved1');
    expect(event.dirty, isFalse);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('task move uses move endpoint and clears dirty', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final (id, remote) in [('l1', 'rl1'), ('l2', 'rl2')]) {
      await db
          .into(db.taskLists)
          .insert(
            TaskListsCompanion.insert(
              id: id,
              remoteId: Value(remote),
              name: id,
              googleAccount: const Value('a@x'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 't1',
            listId: const Value('l2'),
            title: const Value('Moved'),
            remoteId: const Value('task-1'),
            remoteEtag: const Value('old'),
            googleAccount: const Value('a@x'),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-move',
            entity: 'task',
            entityId: 't1',
            op: 'move',
            payload: const Value(
              '{"fromListId":"l1","fromRemoteListId":"rl1"}',
            ),
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake, account: 'a@x');

    await engine.syncNow();

    expect(fake.taskMoves, 1);
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(task.remoteEtag, 'task-moved1');
    expect(task.dirty, isFalse);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('remote delete op runs only under its source account', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-delete',
            entity: 'event_remote',
            entityId: 'e1',
            op: 'delete',
            payload: const Value(
              '{"account":"a@x","calendarRemoteId":"cal-remote",'
              '"eventRemoteId":"g1"}',
            ),
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake, account: 'b@x');
    await engine.syncNow();
    expect(fake.deletedEvents, isEmpty);
    expect(await db.select(db.outbox).get(), hasLength(1));

    final source = SyncEngine(db, clientFactory: () => fake, account: 'a@x');
    await source.syncNow();
    expect(fake.deletedEvents, ['g1']);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('task list create stores remote id and clears dirty', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'l1',
            name: 'Home',
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-create-list',
            entity: 'task_list',
            entityId: 'l1',
            op: 'create',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake, account: 'a@x');

    await engine.syncNow();

    expect(fake.taskListCreates, 1);
    expect(fake.lastTaskListTitle, 'Home');
    final list = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals('l1'))).getSingle();
    expect(list.remoteId, 'rl-new-1');
    expect(list.remoteEtag, 'list-etag-1');
    expect(list.dirty, isFalse);
    expect(list.googleAccount, 'a@x');
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('task list rename patches the remote list', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'l1',
            remoteId: const Value('rl1'),
            name: 'Renamed',
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-update-list',
            entity: 'task_list',
            entityId: 'l1',
            op: 'update',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake);

    await engine.syncNow();

    expect(fake.taskListPatches, 1);
    expect(fake.patchedTaskLists, ['rl1']);
    expect(fake.lastTaskListTitle, 'Renamed');
    final list = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals('l1'))).getSingle();
    expect(list.remoteEtag, 'list-etag-p1');
    expect(list.dirty, isFalse);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('task list delete removes remote then purges local row', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'l1',
            remoteId: const Value('rl1'),
            name: 'Gone',
            createdAt: now,
            updatedAt: now,
            deletedAt: Value(now),
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: 't1',
            listId: const Value('l1'),
            title: const Value('Left behind'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-delete-list',
            entity: 'task_list',
            entityId: 'l1',
            op: 'delete',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake);

    await engine.syncNow();

    expect(fake.deletedTaskLists, ['rl1']);
    expect(await db.select(db.taskLists).get(), isEmpty);
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(task.listId, isNull);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('local-only task list delete just removes the row', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'local',
            name: 'Local',
            createdAt: now,
            updatedAt: now,
            deletedAt: Value(now),
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-delete-local',
            entity: 'task_list',
            entityId: 'local',
            op: 'delete',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final engine = SyncEngine(db, clientFactory: () => fake);

    await engine.syncNow();

    expect(fake.deletedTaskLists, isEmpty);
    expect(await db.select(db.taskLists).get(), isEmpty);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('task list ops are scoped to the active account', () async {
    final db = _db();
    addTearDown(db.close);
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db
        .into(db.taskLists)
        .insert(
          TaskListsCompanion.insert(
            id: 'l1',
            name: 'Theirs',
            googleAccount: const Value('b@x'),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            id: 'op-create-list',
            entity: 'task_list',
            entityId: 'l1',
            op: 'create',
            createdAt: now,
          ),
        );
    final fake = FakeGoogle();
    final first = SyncEngine(db, clientFactory: () => fake, account: 'a@x');
    await first.syncNow();
    expect(fake.taskListCreates, 0);
    expect(await db.select(db.outbox).get(), hasLength(1));

    final second = SyncEngine(db, clientFactory: () => fake, account: 'b@x');
    await second.syncNow();
    expect(fake.taskListCreates, 1);
    final list = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals('l1'))).getSingle();
    expect(list.googleAccount, 'b@x');
    expect(list.remoteId, 'rl-new-1');
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test(
    'discovery does not resurrect a deleted list or duplicate one',
    () async {
      final db = _db();
      addTearDown(db.close);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db
          .into(db.taskLists)
          .insert(
            TaskListsCompanion.insert(
              id: 'tombstone',
              remoteId: const Value('rl-tombstone'),
              name: 'Delete pending',
              createdAt: now,
              updatedAt: now,
              deletedAt: Value(now),
            ),
          );
      await db
          .into(db.taskLists)
          .insert(
            TaskListsCompanion.insert(
              id: 'linked',
              remoteId: const Value('rl-linked'),
              name: 'Linked',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final fake = FakeGoogle()
        ..taskListsResult = [
          {'id': 'rl-tombstone', 'title': 'Remote again'},
          {'id': 'rl-linked', 'title': 'Remote linked'},
        ];
      final engine = SyncEngine(db, clientFactory: () => fake);

      await engine.syncNow();
      await engine.syncNow();

      final tombstone = await (db.select(
        db.taskLists,
      )..where((l) => l.id.equals('tombstone'))).getSingle();
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.name, 'Delete pending');
      final linked = await (db.select(
        db.taskLists,
      )..where((l) => l.remoteId.equals('rl-linked'))).get();
      expect(linked, hasLength(1));
      expect(linked.single.id, 'linked');
    },
  );
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
