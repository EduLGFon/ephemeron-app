import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/domain/tasks/task_sort.dart';
import 'package:ephemeron/features/tasks/application/task_sorting.dart';
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

  test('planned date create, update and clear', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Plan',
      dueDate: '2026-03-10',
      plannedDate: '2026-03-08',
    );
    Future<Task> row() =>
        (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle();
    expect((await row()).plannedDate, '2026-03-08');
    await repo.updateTask(id, plannedDate: () => '2026-03-09');
    expect((await row()).plannedDate, '2026-03-09');
    await repo.updateTask(id, plannedDate: () => null);
    expect((await row()).plannedDate, isNull);
  });

  test('recurring completion shifts planned date with due date', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Weekly review',
      dueDate: '2026-03-02',
      plannedDate: '2026-03-01',
      rrule: 'FREQ=DAILY',
      repeatMode: 'from_due_date',
    );
    await repo.completeTask(id, at: DateTime.utc(2026, 3, 2, 10));
    final open = await repo.evalSmartList({'showCompleted': false});
    expect(open, hasLength(1));
    expect(open.single.dueDate, '2026-03-03');
    expect(open.single.plannedDate, '2026-03-02');
  });

  test('reorder assigns sortOrder without enqueueing Google ops', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final l1 = await repo.createList('A');
    final l2 = await repo.createList('B');
    final l3 = await repo.createList('C');
    final t1 = await repo.createTask(title: 'One', listId: l1);
    final t2 = await repo.createTask(title: 'Two', listId: l1);
    final t3 = await repo.createTask(title: 'Three', listId: l1);
    final outboxBefore = await db.select(db.outbox).get();

    await repo.reorderLists([l3, l1, l2]);
    await repo.reorderTasks([t3, t1, t2]);

    final listOrders = {
      for (final list in await db.select(db.taskLists).get())
        list.id: list.sortOrder,
    };
    expect(listOrders, {l3: 0, l1: 1, l2: 2});
    final taskOrders = {
      for (final task in await db.select(db.tasks).get())
        task.id: task.sortOrder,
    };
    expect(taskOrders, {t3: 0, t1: 1, t2: 2});
    expect((await db.select(db.outbox).get()).length, outboxBefore.length);
  });

  test('task and list sort comparators cover every mode', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final la = await repo.createList('Beta');
    final lb = await repo.createList('alpha');
    final lc = await repo.createList('Gamma');
    for (final (id, created, order) in [
      (la, 100, 0),
      (lb, 300, 1),
      (lc, 200, 2),
    ]) {
      await (db.update(db.taskLists)..where((l) => l.id.equals(id))).write(
        TaskListsCompanion(createdAt: Value(created), sortOrder: Value(order)),
      );
    }
    final ta = await repo.createTask(title: 'Beta', dueDate: '2026-03-03');
    final tb = await repo.createTask(title: 'Alpha');
    final tc = await repo.createTask(title: 'Gamma', dueDate: '2026-03-01');
    for (final (id, created, order) in [
      (ta, 100, 0),
      (tb, 300, 1),
      (tc, 200, 2),
    ]) {
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(createdAt: Value(created), sortOrder: Value(order)),
      );
    }
    final tasks = await db.select(db.tasks).get();
    final lists = await db.select(db.taskLists).get();
    List<String> taskOrder(TaskSort sort) => ([
      ...tasks,
    ]..sort((a, b) => compareTasks(a, b, sort))).map((t) => t.id).toList();
    List<String> listOrder(TaskListSort sort) => ([
      ...lists,
    ]..sort((a, b) => compareTaskLists(a, b, sort))).map((l) => l.id).toList();

    expect(taskOrder(TaskSort.custom), [ta, tb, tc]);
    expect(taskOrder(TaskSort.name), [tb, ta, tc]);
    expect(taskOrder(TaskSort.created), [tb, tc, ta]);
    expect(taskOrder(TaskSort.due), [tc, ta, tb]);
    expect(listOrder(TaskListSort.custom), [la, lb, lc]);
    expect(listOrder(TaskListSort.name), [lb, la, lc]);
    expect(listOrder(TaskListSort.created), [lb, lc, la]);
  });
}
