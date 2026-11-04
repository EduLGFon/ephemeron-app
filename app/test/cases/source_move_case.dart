// Cross-source moves: same-account moves keep remote ids and queue a move;
// cross-account or local moves copy locally and queue deletes for the old
// remote row. Recurring cross-account moves are rejected.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/event_repository.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/domain/sources/source_move.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _calendar(
  AppDatabase db, {
  required String id,
  required String name,
  String? remoteId,
  String? account,
  String source = 'google',
}) async {
  final now = nowMs();
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: id,
          remoteId: Value(remoteId),
          name: name,
          source: Value(source),
          googleAccount: Value(account),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _event(
  AppDatabase db, {
  required String id,
  required String calendarId,
  String? account,
  String? remoteId,
  String? rrule,
}) async {
  final now = nowMs();
  await db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: id,
          calendarId: calendarId,
          title: const Value('Event'),
          startUtc: Value(now),
          endUtc: Value(now + msPerHour),
          rrule: Value(rrule),
          googleAccount: Value(account),
          remoteId: Value(remoteId),
          remoteEtag: Value(remoteId == null ? null : 'etag'),
          dirty: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _list(
  AppDatabase db, {
  required String id,
  required String name,
  String? remoteId,
  String? account,
}) async {
  final now = nowMs();
  await db
      .into(db.taskLists)
      .insert(
        TaskListsCompanion.insert(
          id: id,
          remoteId: Value(remoteId),
          name: name,
          googleAccount: Value(account),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _task(
  AppDatabase db, {
  required String id,
  required String listId,
  String? account,
  String? remoteId,
}) async {
  final now = nowMs();
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          listId: Value(listId),
          title: const Value('Task'),
          googleAccount: Value(account),
          remoteId: Value(remoteId),
          remoteEtag: Value(remoteId == null ? null : 'etag'),
          dirty: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<List<OutboxData>> _outbox(AppDatabase db) => db.select(db.outbox).get();

void main() {
  test('same-account event move keeps remote id and queues move', () async {
    final db = _db();
    addTearDown(db.close);
    await _calendar(
      db,
      id: 'c1',
      name: 'Work',
      remoteId: 'remote1',
      account: 'a@x',
    );
    await _calendar(
      db,
      id: 'c2',
      name: 'Personal',
      remoteId: 'remote2',
      account: 'a@x',
    );
    await _event(
      db,
      id: 'e1',
      calendarId: 'c1',
      account: 'a@x',
      remoteId: 'event1',
    );
    final repo = EventRepository(db, OccurrenceRepository(db));

    await repo.moveEventToCalendar('e1', 'c2');

    final event = await (db.select(
      db.events,
    )..where((e) => e.id.equals('e1'))).getSingle();
    expect(event.calendarId, 'c2');
    expect(event.remoteId, 'event1');
    expect(event.googleAccount, 'a@x');
    final ops = await _outbox(db);
    final move = ops.where((o) => o.op == 'move').single;
    expect(move.payload, contains('remote1'));
    expect(ops.map((o) => o.op), contains('update'));
  });

  test(
    'chained same-account event moves keep the first remote source',
    () async {
      final db = _db();
      addTearDown(db.close);
      await _calendar(
        db,
        id: 'c1',
        name: 'One',
        remoteId: 'remote1',
        account: 'a@x',
      );
      await _calendar(
        db,
        id: 'c2',
        name: 'Two',
        remoteId: 'remote2',
        account: 'a@x',
      );
      await _calendar(
        db,
        id: 'c3',
        name: 'Three',
        remoteId: 'remote3',
        account: 'a@x',
      );
      await _event(
        db,
        id: 'e1',
        calendarId: 'c1',
        account: 'a@x',
        remoteId: 'event1',
      );
      final repo = EventRepository(db, OccurrenceRepository(db));

      await repo.moveEventToCalendar('e1', 'c2');
      await repo.moveEventToCalendar('e1', 'c3');

      final ops = await _outbox(db);
      final move = ops.where((o) => o.op == 'move').single;
      expect(move.payload, contains('remote1'));
      expect(move.payload, isNot(contains('remote2')));
    },
  );

  test('cross-account event move clears remote id and queues delete', () async {
    final db = _db();
    addTearDown(db.close);
    await _calendar(
      db,
      id: 'c1',
      name: 'Work',
      remoteId: 'remote1',
      account: 'a@x',
    );
    await _calendar(
      db,
      id: 'c2',
      name: 'Personal',
      remoteId: 'remote2',
      account: 'b@x',
    );
    await _event(
      db,
      id: 'e1',
      calendarId: 'c1',
      account: 'a@x',
      remoteId: 'event1',
    );
    final repo = EventRepository(db, OccurrenceRepository(db));

    await repo.moveEventToCalendar('e1', 'c2');

    final event = await (db.select(
      db.events,
    )..where((e) => e.id.equals('e1'))).getSingle();
    expect(event.calendarId, 'c2');
    expect(event.googleAccount, 'b@x');
    expect(event.remoteId, isNull);
    expect(event.dirty, isTrue);
    final ops = await _outbox(db);
    expect(ops.map((o) => o.entity), containsAll(['event', 'event_remote']));
    final remoteDelete = ops.firstWhere((o) => o.entity == 'event_remote');
    expect(remoteDelete.payload, contains('a@x'));
    expect(remoteDelete.payload, contains('event1'));
  });

  test('local event target clears dirty and deletes remote only', () async {
    final db = _db();
    addTearDown(db.close);
    await _calendar(
      db,
      id: 'c1',
      name: 'Work',
      remoteId: 'remote1',
      account: 'a@x',
    );
    await _calendar(db, id: 'local', name: 'Local', source: 'device');
    await _event(
      db,
      id: 'e1',
      calendarId: 'c1',
      account: 'a@x',
      remoteId: 'event1',
    );
    final repo = EventRepository(db, OccurrenceRepository(db));

    await repo.moveEventToCalendar('e1', 'local');

    final event = await (db.select(
      db.events,
    )..where((e) => e.id.equals('e1'))).getSingle();
    expect(event.calendarId, 'local');
    expect(event.googleAccount, isNull);
    expect(event.remoteId, isNull);
    expect(event.dirty, isFalse);
    final ops = await _outbox(db);
    expect(ops.map((o) => o.entity), ['event_remote']);
  });

  test('recurring cross-account event move is rejected', () async {
    final db = _db();
    addTearDown(db.close);
    await _calendar(
      db,
      id: 'c1',
      name: 'Work',
      remoteId: 'remote1',
      account: 'a@x',
    );
    await _calendar(
      db,
      id: 'c2',
      name: 'Personal',
      remoteId: 'remote2',
      account: 'b@x',
    );
    await _event(
      db,
      id: 'e1',
      calendarId: 'c1',
      account: 'a@x',
      remoteId: 'event1',
      rrule: 'FREQ=WEEKLY',
    );
    final repo = EventRepository(db, OccurrenceRepository(db));

    expect(
      () => repo.moveEventToCalendar('e1', 'c2'),
      throwsA(isA<SourceMoveException>()),
    );
  });

  test('same-account task move keeps remote id and queues move', () async {
    final db = _db();
    addTearDown(db.close);
    await _list(db, id: 'l1', name: 'Work', remoteId: 'list1', account: 'a@x');
    await _list(db, id: 'l2', name: 'Home', remoteId: 'list2', account: 'a@x');
    await _task(db, id: 't1', listId: 'l1', account: 'a@x', remoteId: 'task1');
    final repo = TaskRepository(db);

    await repo.moveTasks(['t1'], 'l2');

    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(task.listId, 'l2');
    expect(task.remoteId, 'task1');
    final ops = await _outbox(db);
    final move = ops.where((o) => o.op == 'move').single;
    expect(move.payload, contains('list1'));
    expect(ops.map((o) => o.op), contains('update'));
  });

  test('cross-account task move clears remote id and queues delete', () async {
    final db = _db();
    addTearDown(db.close);
    await _list(db, id: 'l1', name: 'Work', remoteId: 'list1', account: 'a@x');
    await _list(db, id: 'l2', name: 'Home', remoteId: 'list2', account: 'b@x');
    await _task(db, id: 't1', listId: 'l1', account: 'a@x', remoteId: 'task1');
    final repo = TaskRepository(db);

    await repo.moveTasks(['t1'], 'l2');

    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(task.listId, 'l2');
    expect(task.googleAccount, 'b@x');
    expect(task.remoteId, isNull);
    final ops = await _outbox(db);
    expect(ops.map((o) => o.entity), containsAll(['task', 'task_remote']));
    final remoteDelete = ops.firstWhere((o) => o.entity == 'task_remote');
    expect(remoteDelete.payload, contains('a@x'));
    expect(remoteDelete.payload, contains('task1'));
  });
}
