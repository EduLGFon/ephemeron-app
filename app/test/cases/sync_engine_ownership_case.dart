// Fake-server suite (ownership/account scoping): discovery stamps, event/task moves, remote-delete gating.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
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
}
