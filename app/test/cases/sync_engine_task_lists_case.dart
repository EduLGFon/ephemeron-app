// Fake-server suite (task lists): create/rename/delete, local-only, account scoping, discovery.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/features/sync/data/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_engine_case.dart' show FakeGoogle;

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
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
