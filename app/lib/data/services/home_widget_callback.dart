import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/habit_repository.dart';
import 'package:ephemeron/data/repositories/task_repository.dart';
import 'package:ephemeron/domain/habits/date_key.dart';

import 'headless_widget_push.dart'
    show cancelAlarmsForEntity, pushHabitWidgets, pushTaskWidgets;

/// Parsed widget toggle action. Pure and unit-testable.
class ToggleRequest {
  const ToggleRequest(this.kind, this.id);
  final String kind;
  final String id;
}

/// Parses `ephemeron://toggle/<kind>/<id>` URIs. Returns null when the URI
/// is not a toggle action.
ToggleRequest? parseToggleUri(Uri? uri) {
  if (uri == null) return null;
  final segments = uri.pathSegments;
  // Form 1 (used by the widgets): ephemeron://toggle/<kind>/<id>
  // (host == 'toggle', path == /<kind>/<id>).
  if (uri.host == 'toggle' && segments.length >= 2) {
    final kind = segments[0];
    final id = segments[1];
    if ((kind == 'task' || kind == 'habit') && id.isNotEmpty) {
      return ToggleRequest(kind, id);
    }
    return null;
  }
  // Form 2 (path-based): ephemeron:///toggle/<kind>/<id>.
  if (segments.length >= 3 && segments[0] == 'toggle') {
    final kind = segments[1];
    final id = segments[2];
    if ((kind == 'task' || kind == 'habit') && id.isNotEmpty) {
      return ToggleRequest(kind, id);
    }
  }
  return null;
}

@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  final req = parseToggleUri(uri);
  if (req == null) return;
  AppDatabase? db;
  try {
    db = AppDatabase();
    if (req.kind == 'task') {
      await TaskRepository(db).completeTask(req.id);
      await cancelAlarmsForEntity(db, req.id);
      // Push the updated list so the widget reflects the tap.
      await pushTaskWidgets(db);
    } else if (req.kind == 'habit') {
      await HabitRepository(db).logDone(req.id, habitDateKey(DateTime.now()));
      await cancelAlarmsForEntity(db, req.id);
      await pushHabitWidgets(db);
    }
  } catch (_) {
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}
