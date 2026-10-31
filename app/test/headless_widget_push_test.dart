import 'package:drift/native.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/data/services/headless_widget_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('headless push does not throw on empty db', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await pushAllHeadlessWidgets(db);
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
