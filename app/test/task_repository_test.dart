import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
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
}
