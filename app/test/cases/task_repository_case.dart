import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test('create list and task, complete recurring creates next', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final listId = await repo.createList('Home');
    final id = await repo.createTask(
      title: 'Water plants',
      listId: listId,
      dueDate: '2026-03-02',
      rrule: 'FREQ=DAILY',
      repeatMode: 'from_due_date',
    );
    await repo.completeTask(id, at: DateTime.utc(2026, 3, 2, 10));
    final open = await repo.evalSmartList({'showCompleted': false});
    expect(open.length, 1);
    expect(open.single.dueDate, '2026-03-03');
    expect(open.single.completedAt, isNull);
  });

  test('skip occurrence advances due without completing', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Gym',
      dueDate: '2026-03-02',
      rrule: 'FREQ=DAILY',
    );
    await repo.skipOccurrence(id);
    final tasks = await repo.evalSmartList({'showCompleted': false});
    expect(tasks.single.dueDate, '2026-03-03');
    expect(tasks.single.completedAt, isNull);
  });

  test('trash, restore and purge', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'Temp');
    await repo.softDeleteTasks([id]);
    expect(await repo.watchTrash().first, hasLength(1));
    expect(await repo.watchOpen().first, isEmpty);
    await repo.restoreTasks([id]);
    expect(await repo.watchOpen().first, hasLength(1));
    await repo.softDeleteTasks([id]);
    await repo.purgeTask(id);
    expect(await repo.watchTrash().first, isEmpty);
  });

  test('pending delete and purge hide optimistically', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final pending = PendingOperationsRepository(db);
    final id = await repo.createTask(title: 'Temp');

    final open = repo.watchOpen();
    final emptyUpdate = open
        .firstWhere((rows) => rows.isEmpty)
        .timeout(const Duration(seconds: 2));
    final deleteOp = await pending.enqueue(
      entity: 'task',
      entityId: id,
      op: 'delete',
    );
    expect(await emptyUpdate, isEmpty);
    final restored = open
        .firstWhere((rows) => rows.isNotEmpty)
        .timeout(const Duration(seconds: 2));
    await pending.cancel(deleteOp);
    expect(await restored, hasLength(1));

    await repo.softDeleteTasks([id]);
    final purgeOp = await pending.enqueue(
      entity: 'task',
      entityId: id,
      op: 'purge',
    );
    expect(await repo.watchTrash().first, isEmpty);
    await pending.cancel(purgeOp);
    expect(await repo.watchTrash().first, hasLength(1));
  });

  test('tags and smart list filter', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final a = await repo.createTask(title: 'A', priority: 4, tags: ['work']);
    await repo.createTask(title: 'B', priority: 1, tags: ['home']);
    final tagId = await repo.ensureTag('work');
    final byTag = await repo.evalSmartList({
      'tagIds': [tagId],
      'showCompleted': true,
    });
    expect(byTag.map((t) => t.id), [a]);
    final byPri = await repo.evalSmartList({
      'priorities': [4],
      'showCompleted': true,
    });
    expect(byPri.map((t) => t.id), [a]);
  });

  test('subtasks progress and move with undo mapping', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final l1 = await repo.createList('L1');
    final l2 = await repo.createList('L2');
    final parent = await repo.createTask(title: 'P', listId: l1);
    final sub = await repo.createTask(title: 'S', parentId: parent);
    expect(await repo.subtaskProgress(parent), [0, 1]);
    await repo.completeTask(sub);
    expect(await repo.subtaskProgress(parent), [1, 1]);
    final prev = await repo.moveTasks([parent], l2);
    expect(prev[parent], l1);
  });

  test('move undo restores previous list', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final l1 = await repo.createList('A');
    final l2 = await repo.createList('B');
    final t = await repo.createTask(title: 'T', listId: l1);
    final prev = await repo.moveTasks([t], l2);
    expect(prev[t], l1);
    for (final e in prev.entries) {
      await repo.moveTasks([e.key], e.value);
    }
    final row = await (db.select(
      db.tasks,
    )..where((x) => x.id.equals(t))).getSingle();
    expect(row.listId, l1);
  });

  test('task reminders and alarm preset persist', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Report',
      dueDate: '2026-03-02',
      reminders: '[5,0]',
      alarmPreset: 'full_short',
    );
    var row = await (db.select(
      db.tasks,
    )..where((x) => x.id.equals(id))).getSingle();
    expect(row.reminders, '[5,0]');
    expect(row.alarmPreset, 'full_short');
    await repo.updateTask(id, reminders: () => '[60]', alarmPreset: () => null);
    row = await (db.select(
      db.tasks,
    )..where((x) => x.id.equals(id))).getSingle();
    expect(row.reminders, '[60]');
    expect(row.alarmPreset, isNull);
  });

  test('update list queues patch; delete hides and tombstones', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final first = await repo.createList('Home', color: '#111111');
    final second = await repo.createList('Work');
    await repo.updateList(first, name: 'House', color: '#222222');
    await (db.update(db.taskLists)..where((l) => l.id.equals(second))).write(
      const TaskListsCompanion(remoteId: Value('remote-second')),
    );
    final updated = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals(first))).getSingle();
    expect(updated.name, 'House');
    expect(updated.color, '#222222');
    expect(updated.dirty, isTrue);
    final patch =
        await (db.select(db.outbox)..where(
              (o) =>
                  o.entity.equals('task_list') &
                  o.entityId.equals(first) &
                  o.op.equals('update'),
            ))
            .getSingle();
    expect(patch.entity, 'task_list');

    await repo.deleteList(second);
    expect((await repo.watchLists().first).map((l) => l.id), [first]);
    final deleted = await (db.select(
      db.taskLists,
    )..where((l) => l.id.equals(second))).getSingle();
    expect(deleted.deletedAt, isNotNull);
    expect(deleted.dirty, isTrue);
    expect(deleted.remoteId, 'remote-second');
    expect(
      await (db.select(db.outbox)..where(
            (o) =>
                o.entity.equals('task_list') &
                o.entityId.equals(second) &
                o.op.equals('delete'),
          ))
          .get(),
      hasLength(1),
    );
  });

  test('delete list moves tasks or sends them to trash', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final source = await repo.createList('Source');
    final target = await repo.createList('Target');
    final movedA = await repo.createTask(title: 'A', listId: source);
    final movedB = await repo.createTask(title: 'B', listId: source);
    await repo.deleteList(source, moveTasksToListId: target);
    for (final id in [movedA, movedB]) {
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.listId, target);
      expect(row.deletedAt, isNull);
    }

    final doomed = await repo.createList('Doomed');
    final deletedA = await repo.createTask(title: 'C', listId: doomed);
    final deletedB = await repo.createTask(title: 'D', listId: doomed);
    await repo.deleteList(doomed, deleteTasks: true);
    for (final id in [deletedA, deletedB]) {
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.deletedAt, isNotNull);
    }

    final unlistedSource = await repo.createList('Unlisted');
    final unlisted = await repo.createTask(title: 'E', listId: unlistedSource);
    await repo.deleteList(unlistedSource);
    final unlistedRow = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(unlisted))).getSingle();
    expect(unlistedRow.listId, isNull);
    expect(unlistedRow.deletedAt, isNull);
  });

  test('smart list create, update, delete and reactive watch', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createSmartList('Mine', {
      'showCompleted': false,
      'sort': 'title',
    });
    expect((await repo.watchSmartLists().first).single.name, 'Mine');
    final stream = repo.watchSmartList({
      'priorities': [4],
      'showCompleted': true,
    });
    final matched = stream.firstWhere((rows) => rows.isNotEmpty);
    final task = await repo.createTask(title: 'Important', priority: 4);
    expect((await matched).map((t) => t.id), [task]);

    await repo.updateSmartList(
      id,
      name: 'Renamed',
      filter: {
        'priorities': [1],
        'sort': 'priority',
      },
    );
    final row = (await repo.watchSmartLists().first).single;
    expect(row.name, 'Renamed');
    expect(row.filterJson, contains('"sort":"priority"'));
    await repo.deleteSmartList(id);
    expect(await repo.watchSmartLists().first, isEmpty);
  });

  test(
    'smart filter matches list, tag, priority, due, query, completed',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = TaskRepository(db);
      final work = await repo.createList('Work');
      final home = await repo.createList('Home');
      final a = await repo.createTask(
        title: 'Send report',
        notes: 'quarterly numbers',
        listId: work,
        priority: 4,
        dueDate: '2026-03-10',
        tags: ['office'],
      );
      final b = await repo.createTask(
        title: 'Buy milk',
        listId: home,
        priority: 1,
        dueDate: '2026-03-20',
      );
      final c = await repo.createTask(
        title: 'Call bank',
        listId: work,
        dueDate: '2026-04-01',
      );
      await repo.completeTask(b);
      final office = await repo.ensureTag('office');

      Future<List<String>> ids(Map<String, Object?> filter) async => [
        for (final task in await repo.evalSmartList(filter)) task.id,
      ];

      expect(
        await ids({
          'listIds': [work],
          'showCompleted': true,
        }),
        [a, c],
      );
      expect(
        await ids({
          'tagIds': [office],
          'showCompleted': true,
        }),
        [a],
      );
      expect(
        await ids({
          'priorities': [4],
          'showCompleted': true,
        }),
        [a],
      );
      expect(
        await ids({
          'dueFrom': '2026-03-01',
          'dueTo': '2026-03-31',
          'showCompleted': true,
        }),
        [a, b],
      );
      expect(await ids({'query': 'numbers', 'showCompleted': true}), [a]);
      expect(await ids({'query': 'MILK', 'showCompleted': true}), [b]);
      expect(await ids({'showCompleted': false}), isNot(contains(b)));
      expect(await ids({'showCompleted': true}), contains(b));
    },
  );

  test('smart filter applies due, priority, created and title sorts', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final ids = <String, String>{};
    for (final (key, title, due, priority, created) in [
      ('a', 'Beta', '2026-03-03', 1, 100),
      ('b', 'Alpha', '2026-03-01', 4, 300),
      ('c', 'Gamma', '2026-03-02', 2, 200),
    ]) {
      final id = await repo.createTask(
        title: title,
        dueDate: due,
        priority: priority,
      );
      ids[key] = id;
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(createdAt: Value(created)),
      );
    }
    Future<List<String>> run(String sort) async {
      final rows = await repo.evalSmartList({
        'showCompleted': true,
        'sort': sort,
      });
      return [for (final row in rows) row.id];
    }

    expect(await run('due'), [ids['b'], ids['c'], ids['a']]);
    expect(await run('priority'), [ids['b'], ids['c'], ids['a']]);
    expect(await run('created'), [ids['b'], ids['c'], ids['a']]);
    expect(await run('title'), [ids['b'], ids['a'], ids['c']]);
  });

  test('smart due windows use the saved preset', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final now = DateTime.now();
    String key(int offset) {
      final d = DateTime(now.year, now.month, now.day + offset);
      return '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    final overdue = await repo.createTask(title: 'Overdue', dueDate: key(-1));
    final today = await repo.createTask(title: 'Today', dueDate: key(0));
    final soon = await repo.createTask(title: 'Soon', dueDate: key(6));
    final later = await repo.createTask(title: 'Later', dueDate: key(7));
    expect(
      (await repo.evalSmartList({'dueWindow': 'today'})).map((t) => t.id),
      [today],
    );
    expect(
      (await repo.evalSmartList({'dueWindow': 'overdue'})).map((t) => t.id),
      [overdue],
    );
    expect(
      (await repo.evalSmartList({'dueWindow': 'next7Days'})).map((t) => t.id),
      [today, soon],
    );
    expect(
      (await repo.evalSmartList({'dueWindow': 'next7Days'})).map((t) => t.id),
      isNot(contains(later)),
    );
  });
}
