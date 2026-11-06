import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  test(
    'recurring completion shifts planned interval and keeps series',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = TaskRepository(db);
      final id = await repo.createTask(
        title: 'Plan block',
        dueDate: '2026-03-02',
        plannedStart: '2026-03-01T10:00',
        plannedEnd: '2026-03-01T11:00',
        rrule: 'FREQ=DAILY',
        repeatMode: 'from_due_date',
      );
      final original = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      await repo.completeTask(id, at: DateTime.utc(2026, 3, 2, 10));
      final open = await repo.evalSmartList({'showCompleted': false});
      expect(open, hasLength(1));
      final t = open.single;
      expect(t.dueDate, '2026-03-03');
      expect(t.plannedStart, '2026-03-02T10:00');
      expect(t.plannedEnd, '2026-03-02T11:00');
      expect(t.seriesId, original.seriesId);
      expect(t.recurrenceKey, '2026-03-03');
    },
  );

  test(
    'planned-only recurring completion advances series and keeps null due',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = TaskRepository(db);
      final id = await repo.createTask(
        title: 'Plan only',
        plannedStart: '2026-03-01T10:00',
        plannedEnd: '2026-03-01T11:00',
        rrule: 'FREQ=DAILY',
        repeatMode: 'from_due_date',
      );
      final original = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      await repo.completeTask(id, at: DateTime.utc(2026, 3, 1, 10));
      final open = await repo.evalSmartList({'showCompleted': false});
      expect(open, hasLength(1));
      final t = open.single;
      expect(t.dueDate, isNull);
      expect(t.plannedStart, '2026-03-02T10:00');
      expect(t.plannedEnd, '2026-03-02T11:00');
      expect(t.seriesId, original.seriesId);
      expect(t.recurrenceKey, isNotNull);
    },
  );

  test('markWontDo sets wontDo and completedAt and advances series', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Skip me',
      dueDate: '2026-03-02',
      rrule: 'FREQ=DAILY',
      repeatMode: 'from_due_date',
    );
    final original = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await repo.markWontDo(id, at: DateTime.utc(2026, 3, 2, 10));
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.wontDo, isTrue);
    expect(row.completedAt, isNotNull);
    final open = await repo.evalSmartList({'showCompleted': false});
    expect(open, hasLength(1));
    expect(open.single.dueDate, '2026-03-03');
    expect(open.single.seriesId, original.seriesId);
  });

  test('skipOccurrence advances planned interval', () async {
    final db = _db();
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Gym',
      dueDate: '2026-03-02',
      plannedStart: '2026-03-02T09:00',
      plannedEnd: '2026-03-02T10:00',
      rrule: 'FREQ=DAILY',
    );
    await repo.skipOccurrence(id);
    final tasks = await repo.evalSmartList({'showCompleted': false});
    expect(tasks.single.dueDate, '2026-03-03');
    expect(tasks.single.plannedStart, '2026-03-03T09:00');
    expect(tasks.single.plannedEnd, '2026-03-03T10:00');
    expect(tasks.single.completedAt, isNull);
  });

  test(
    'projected occurrence state is local-only and does not advance series',
    () async {
      final db = _db();
      addTearDown(db.close);
      final repo = TaskRepository(db);
      final id = await repo.createTask(
        title: 'Recur',
        dueDate: '2026-03-02',
        rrule: 'FREQ=DAILY',
        repeatMode: 'from_due_date',
      );
      await (db.delete(db.outbox)).go();
      await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
        const TasksCompanion(dirty: Value(false)),
      );
      final task = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();

      await repo.completeTaskOccurrence(task, '2026-03-10');
      var states = await db.select(db.taskOccurrenceStates).get();
      expect(states, hasLength(1));
      expect(states.single.seriesId, task.seriesId ?? task.id);
      expect(states.single.occurrenceDate, '2026-03-10');
      expect(states.single.status, 'completed');
      var row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.completedAt, isNull);
      expect(row.dirty, isFalse);
      expect(row.dueDate, '2026-03-02');
      expect(await db.select(db.outbox).get(), isEmpty);

      await repo.markWontDoTaskOccurrence(task, '2026-03-11');
      states = await db.select(db.taskOccurrenceStates).get();
      expect(
        states.map((s) => s.occurrenceDate),
        containsAll(['2026-03-10', '2026-03-11']),
      );
      expect(
        states.firstWhere((s) => s.occurrenceDate == '2026-03-11').status,
        'wont_do',
      );

      await repo.uncompleteTaskOccurrence(task, '2026-03-10');
      states = await db.select(db.taskOccurrenceStates).get();
      expect(states.map((s) => s.occurrenceDate), ['2026-03-11']);
      row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.completedAt, isNull);
      expect(await db.select(db.outbox).get(), isEmpty);
    },
  );
}
