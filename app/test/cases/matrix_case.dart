import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:ephemeron/features/tasks/presentation/matrix_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('auto mode groups tasks into four fields and a tray', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    final now = DateTime.now();
    final urgent = _date(now.add(const Duration(days: 1)));
    final later = _date(now.add(const Duration(days: 30)));
    await repo.createTask(title: 'Do first task', priority: 3, dueDate: urgent);
    await repo.createTask(title: 'Schedule task', priority: 3, dueDate: later);
    await repo.createTask(title: 'Delegate task', priority: 1, dueDate: urgent);
    await repo.createTask(title: 'Eliminate task', priority: 1, dueDate: later);
    await repo.createTask(title: 'Unclassified task');

    await _pumpMatrix(tester, db);

    expect(_inField('doFirst', 'Do first task'), findsOneWidget);
    expect(_inField('schedule', 'Schedule task'), findsOneWidget);
    expect(_inField('delegate', 'Delegate task'), findsOneWidget);
    expect(_inField('eliminate', 'Eliminate task'), findsOneWidget);
    expect(_inTray('Unclassified task'), findsOneWidget);
    expect(_count('doFirst'), '1');
    expect(_count('schedule'), '1');
    expect(_count('delegate'), '1');
    expect(_count('eliminate'), '1');
    expect(_trayCount(), '1');
    expect(find.byKey(const Key('matrix-add-task')), findsOneWidget);

    await _dispose(tester, db);
  });

  testWidgets('priority mode groups P1-P4 and persists the choice', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    await repo.createTask(title: 'P1 task', priority: 4);
    await repo.createTask(title: 'P2 task', priority: 3);
    await repo.createTask(title: 'P3 task', priority: 2);
    await repo.createTask(title: 'P4 task', priority: 1);
    await repo.createTask(title: 'No priority task');

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_inField('p1', 'P1 task'), findsOneWidget);
    expect(_inField('p2', 'P2 task'), findsOneWidget);
    expect(_inField('p3', 'P3 task'), findsOneWidget);
    expect(_inField('p4', 'P4 task'), findsOneWidget);
    expect(_inTray('No priority task'), findsOneWidget);
    expect(_count('p1'), '1');
    expect(_count('p2'), '1');
    expect(_count('p3'), '1');
    expect(_count('p4'), '1');
    expect(_trayCount(), '1');
    expect(find.text('Do first'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(SettingsRepository(prefs).matrixMode, 'priority');

    // A fresh screen restores the persisted mode.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: MatrixScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_inField('p1', 'P1 task'), findsOneWidget);
    expect(find.text('Do first'), findsNothing);

    await _dispose(tester, db);
  });

  testWidgets('priority mode drag moves a P4 task into P1', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    await repo.createTask(title: 'P1 task', priority: 4);
    final p4Id = await repo.createTask(title: 'P4 task', priority: 1);

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_inField('p4', 'P4 task'), findsOneWidget);
    expect(_count('p1'), '1');

    final row = find.byKey(ValueKey('matrix-task-$p4Id'));
    final target = find.byKey(const ValueKey('matrix-field-p1'));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_inField('p1', 'P4 task'), findsOneWidget);
    expect(_inField('p4', 'P4 task'), findsNothing);
    expect(_count('p1'), '2');
    expect(_count('p4'), '0');

    await _dispose(tester, db);
  });

  testWidgets('priority mode drag moves a field task to unclassified', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'P1 task', priority: 4);
    await repo.createTask(title: 'P2 task', priority: 3);

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(_inField('p1', 'P1 task'), findsOneWidget);
    expect(_trayCount(), '0');

    final row = find.byKey(ValueKey('matrix-task-$id'));
    final target = find.byKey(const ValueKey('matrix-unclassified'));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_inTray('P1 task'), findsOneWidget);
    expect(_inField('p1', 'P1 task'), findsNothing);
    expect(_count('p1'), '0');
    expect(_trayCount(), '1');

    await _dispose(tester, db);
  });

  testWidgets('dropping a task on its own field is a no-op', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'P1 task', priority: 4);

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final row = find.byKey(ValueKey('matrix-task-$id'));
    final target = find.byKey(const ValueKey('matrix-field-p1'));
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('P1 task'), findsOneWidget);
    expect(_inField('p1', 'P1 task'), findsOneWidget);
    expect(_count('p1'), '1');
    expect(_trayCount(), '0');

    await _dispose(tester, db);
  });

  testWidgets('tapping task text opens the editor', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'P1 task', priority: 4);

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final text = find.descendant(
      of: find.byKey(ValueKey('matrix-task-$id')),
      matching: find.text('P1 task'),
    );
    await tester.tap(text);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Notes'), findsOneWidget);

    await _dispose(tester, db);
  });

  testWidgets('priority mode checkbox completes a task and undo restores it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'P1 task', priority: 4);

    await _pumpMatrix(tester, db);
    await tester.tap(find.text('Priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(ValueKey('matrix-complete-$id')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('P1 task'), findsNothing);
    expect(find.text('Completed "P1 task"'), findsOneWidget);
    expect(_count('p1'), '0');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(_inField('p1', 'P1 task'), findsOneWidget);
    expect(_count('p1'), '1');

    await _dispose(tester, db);
  });

  testWidgets('auto mode has no draggable rows or drop targets', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    await repo.createTask(
      title: 'Auto task',
      priority: 3,
      dueDate: _date(DateTime.now().add(const Duration(days: 1))),
    );

    await _pumpMatrix(tester, db);

    expect(find.byType(LongPressDraggable<Task>), findsNothing);
    expect(find.byType(DragTarget<Task>), findsNothing);

    await _dispose(tester, db);
  });

  testWidgets('board scrolls at 320dp without overflow', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    for (var i = 0; i < 6; i++) {
      await repo.createTask(
        title: 'Task number $i with a fairly long title',
        priority: i % 4,
      );
    }

    await _pumpMatrix(tester, db);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('matrix-unclassified')), findsOneWidget);
    expect(find.byKey(const Key('matrix-add-task')), findsOneWidget);

    await _dispose(tester, db);
  });
}

Future<void> _pumpMatrix(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: MatrixScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _dispose(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
  await tester.pump();
}

Finder _inField(String fieldId, String text) {
  return find.descendant(
    of: find.byKey(ValueKey('matrix-field-$fieldId')),
    matching: find.text(text),
  );
}

Finder _inTray(String text) {
  return find.descendant(
    of: find.byKey(const ValueKey('matrix-unclassified')),
    matching: find.text(text),
  );
}

String? _count(String fieldId) {
  final text = find.byKey(ValueKey('matrix-count-$fieldId'));
  return (text.evaluate().single.widget as Text).data;
}

String? _trayCount() {
  final text = find.byKey(const ValueKey('matrix-count-unclassified'));
  return (text.evaluate().single.widget as Text).data;
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
