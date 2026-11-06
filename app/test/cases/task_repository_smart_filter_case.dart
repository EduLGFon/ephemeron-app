import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
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
