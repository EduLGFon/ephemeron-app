import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/features/settings/application/settings_providers.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:ephemeron/features/tasks/presentation/task_editor_sheet.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _openEditor(
  WidgetTester tester,
  AppDatabase db, {
  Task? task,
  Map<String, dynamic>? draft,
}) async {
  const channel = MethodChannel('ephemeron/system');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canPostNotifications') return true;
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWith(
          (ref) async => SettingsRepository(prefs),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showTaskEditor(context, task: task, restoredDraft: draft),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _selectRepeat(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<String?>).first;
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  final item = find.text(label).last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _close(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
  await tester.pump();
}

final _customRruleField = find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Custom RRULE',
);

void main() {
  testWidgets('repeat preset Daily saves rrule on create', (tester) async {
    final db = _db();
    await _openEditor(tester, db);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'T1');
    await tester.pump();
    await _selectRepeat(tester, 'Daily');
    await _save(tester, 'Create');

    final rows = await db.select(db.tasks).get();
    expect(rows, hasLength(1));
    expect(rows.single.rrule, 'FREQ=DAILY');
    await _close(tester, db);
  });

  testWidgets('repeat preset Weekly saves rrule on update', (tester) async {
    final db = _db();
    final repo = TaskRepository(db);
    final id = await repo.createTask(title: 'T2');
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await _openEditor(tester, db, task: task);
    await _selectRepeat(tester, 'Weekly');
    await _save(tester, 'Save');

    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.rrule, 'FREQ=WEEKLY');
    await _close(tester, db);
  });

  testWidgets('custom valid rrule saves', (tester) async {
    final db = _db();
    await _openEditor(tester, db);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'T3');
    await tester.pump();
    await _selectRepeat(tester, 'Custom RRULE');
    await tester.enterText(_customRruleField, 'FREQ=DAILY;INTERVAL=2');
    await tester.pump();
    await _save(tester, 'Create');

    final rows = await db.select(db.tasks).get();
    expect(rows, hasLength(1));
    expect(rows.single.rrule, 'FREQ=DAILY;INTERVAL=2');
    await _close(tester, db);
  });

  testWidgets('invalid custom rrule shows validation and does not save', (
    tester,
  ) async {
    final db = _db();
    await _openEditor(tester, db);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'T4');
    await tester.pump();
    await _selectRepeat(tester, 'Custom RRULE');
    await tester.enterText(_customRruleField, 'NOT AN RRULE');
    await tester.pump();
    await _save(tester, 'Create');

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(find.text('Invalid recurrence rule.'), findsOneWidget);
    await _close(tester, db);
  });

  testWidgets(
    'restored draft planned interval saves and replaces planned date',
    (tester) async {
      final db = _db();
      await _openEditor(
        tester,
        db,
        draft: const {
          'title': 'Planned',
          'plannedDate': '2026-02-01',
          'plannedStart': '2026-02-02T09:00',
          'plannedEnd': '2026-02-02T10:00',
        },
      );
      await _save(tester, 'Create');

      final rows = await db.select(db.tasks).get();
      expect(rows, hasLength(1));
      expect(rows.single.plannedStart, '2026-02-02T09:00');
      expect(rows.single.plannedEnd, '2026-02-02T10:00');
      expect(rows.single.plannedDate, isNull);
      await _close(tester, db);
    },
  );

  testWidgets('planned end before start is rejected', (tester) async {
    final db = _db();
    await _openEditor(
      tester,
      db,
      draft: const {
        'title': 'Bad interval',
        'plannedStart': '2026-02-02T10:00',
        'plannedEnd': '2026-02-02T09:00',
      },
    );
    await _save(tester, 'Create');

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(find.text('Planned end must be after start.'), findsOneWidget);
    await _close(tester, db);
  });

  testWidgets('clearing the planned interval clears both values', (
    tester,
  ) async {
    final db = _db();
    final repo = TaskRepository(db);
    final id = await repo.createTask(
      title: 'Clear me',
      plannedStart: '2026-02-02T09:00',
      plannedEnd: '2026-02-02T10:00',
    );
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    await _openEditor(tester, db, task: task);
    await tester.tap(find.byTooltip('Clear interval'));
    await tester.pump();
    await _save(tester, 'Save');

    final row = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.plannedStart, isNull);
    expect(row.plannedEnd, isNull);
    await _close(tester, db);
  });
}
