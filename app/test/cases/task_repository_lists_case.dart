import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
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
}
