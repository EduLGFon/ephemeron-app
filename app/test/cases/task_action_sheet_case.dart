import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/features/calendar/presentation/task_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seedTask(
  AppDatabase db, {
  String id = 't1',
  String title = 'Task',
  String? parentId,
  String? plannedStart,
  String? plannedDate,
  String? dueDate,
  int? dueTime,
  String? plannedEnd,
  String? rrule,
  String? seriesId,
  String? recurrenceKey,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.tasks)
      .insert(
        TasksCompanion.insert(
          id: id,
          parentId: Value(parentId),
          title: Value(title),
          plannedStart: Value(plannedStart),
          plannedEnd: Value(plannedEnd),
          plannedDate: Value(plannedDate),
          dueDate: Value(dueDate),
          dueTime: Value(dueTime),
          rrule: Value(rrule),
          seriesId: Value(seriesId),
          recurrenceKey: Value(recurrenceKey),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _pumpSheet(
  WidgetTester tester,
  AppDatabase db,
  String taskId,
  String occurrenceDate,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showTaskActionSheet(
                ctx,
                taskId: taskId,
                occurrenceDate: occurrenceDate,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

void main() {
  testWidgets('mark as concluded completes task and closes sheet', (
    tester,
  ) async {
    final db = _db();
    try {
      await _seedTask(db, dueDate: '2026-01-01');
      await _pumpSheet(tester, db, 't1', '2026-01-01');
      expect(find.text('Mark as concluded'), findsOneWidget);
      await tester.tap(find.text('Mark as concluded'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Mark as concluded'), findsNothing);
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('t1'))).getSingle();
      expect(row.completedAt, isNotNull);
    } finally {
      await _tearDown(tester, db);
    }
  });

  testWidgets("won't do sets wontDo", (tester) async {
    final db = _db();
    try {
      await _seedTask(db, dueDate: '2026-01-01');
      await _pumpSheet(tester, db, 't1', '2026-01-01');
      await tester.tap(find.text("Won't do"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('t1'))).getSingle();
      expect(row.wontDo, isTrue);
    } finally {
      await _tearDown(tester, db);
    }
  });

  testWidgets('subtask circle toggles completion', (tester) async {
    final db = _db();
    try {
      await _seedTask(db, dueDate: '2026-01-01');
      await _seedTask(
        db,
        id: 's1',
        parentId: 't1',
        title: 'Sub',
        dueDate: '2026-01-01',
      );
      await _pumpSheet(tester, db, 't1', '2026-01-01');
      expect(find.text('Sub'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.radio_button_unchecked_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('s1'))).getSingle();
      expect(row.completedAt, isNotNull);
    } finally {
      await _tearDown(tester, db);
    }
  });

  testWidgets(
    'projected recurring occurrence completes per-occurrence without advancing series',
    (tester) async {
      final db = _db();
      try {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 't1',
                title: const Value('Recur'),
                dueDate: const Value('2020-01-01'),
                rrule: const Value('FREQ=DAILY'),
                seriesId: const Value('s1'),
                recurrenceKey: const Value('2020-01-01'),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _pumpSheet(tester, db, 't1', '2030-01-01');
        expect(find.text('Future occurrence'), findsOneWidget);
        expect(find.text('Mark as concluded'), findsOneWidget);
        expect(find.text("Won't do"), findsOneWidget);
        await tester.tap(find.text('Mark as concluded'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final row = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals('t1'))).getSingle();
        expect(row.completedAt, isNull);
        expect(row.dueDate, '2020-01-01');
        final states = await db.select(db.taskOccurrenceStates).get();
        expect(states, hasLength(1));
        expect(states.single.seriesId, 's1');
        expect(states.single.occurrenceDate, '2030-01-01');
        expect(states.single.status, 'completed');
      } finally {
        await _tearDown(tester, db);
      }
    },
  );

  testWidgets("projected recurring occurrence won't do writes local state", (
    tester,
  ) async {
    final db = _db();
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 't1',
              title: const Value('Recur'),
              dueDate: const Value('2020-01-01'),
              rrule: const Value('FREQ=DAILY'),
              seriesId: const Value('s1'),
              recurrenceKey: const Value('2020-01-01'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _pumpSheet(tester, db, 't1', '2020-01-02');
      await tester.tap(find.text("Won't do"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('t1'))).getSingle();
      expect(row.completedAt, isNull);
      expect(row.wontDo, isFalse);
      final states = await db.select(db.taskOccurrenceStates).get();
      expect(states, hasLength(1));
      expect(states.single.status, 'wont_do');
    } finally {
      await _tearDown(tester, db);
    }
  });

  testWidgets('planned interval shows start and end time', (tester) async {
    final db = _db();
    try {
      await _seedTask(
        db,
        plannedStart: '2026-01-01T09:00',
        plannedEnd: '2026-01-01T10:30',
        dueDate: '2026-01-01',
        dueTime: 60,
      );
      await _pumpSheet(tester, db, 't1', '2026-01-01');
      expect(find.textContaining('09:00'), findsOneWidget);
      expect(find.textContaining('10:30'), findsOneWidget);
    } finally {
      await _tearDown(tester, db);
    }
  });
}
