import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/data/services/headless_widget_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('headless push does not throw on empty db', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await pushAllHeadlessWidgets(db);
  });

  test('toggle cancels scheduled alarms for the entity', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.alarmsIndex)
        .insert(
          AlarmsIndexCompanion.insert(
            id: Uuid().v4(),
            sourceType: 'task_reminder',
            sourceId: 'task-1#r0',
            fireAtUtc: DateTime.now().millisecondsSinceEpoch + 60000,
            requestCode: const Value(424201),
            state: const Value('scheduled'),
          ),
        );
    await cancelAlarmsForEntity(db, 'task-1');
    final rows = await db.select(db.alarmsIndex).get();
    expect(rows.single.state, 'cancelled');
    // Unknown ids are a no-op.
    await cancelAlarmsForEntity(db, 'nope');
  });

  test('headless task push honors list filter', () async {
    SharedPreferences.setMockInitialValues({
      'widget_config_PendingTasksWidgetProvider': 'list-a',
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = TaskRepository(db);
    final listId = await repo.createList('A');
    await repo.createTask(title: 'in list', listId: listId);
    expect(await readWidgetBinding('PendingTasksWidgetProvider'), 'list-a');
    await pushTaskWidgets(db, listId: listId);
  });
}
