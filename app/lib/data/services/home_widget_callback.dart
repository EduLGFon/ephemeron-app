import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/domain/habits/date_key.dart';
import 'package:home_widget/home_widget.dart';

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  try {
    final db = AppDatabase();
    try {
      final segments = uri.pathSegments;
      if (segments.length >= 3 && segments[0] == 'toggle') {
        final kind = segments[1];
        final id = segments[2];
        if (kind == 'task') {
          final repo = TaskRepository(db);
          await repo.completeTask(id);
        } else if (kind == 'habit') {
          final repo = HabitRepository(db);
          await repo.logDone(id, habitDateKey(DateTime.now()));        }
      }
      await HomeWidget.saveWidgetData<String>('sync_status_title', 'Updated');
      await HomeWidget.updateWidget(
        androidName: 'SyncStatusWidgetProvider',
        qualifiedAndroidName: 'com.spotnik.ephemeron.SyncStatusWidgetProvider',
      );
    } finally {
      await db.close();
    }
  } catch (_) {}
}