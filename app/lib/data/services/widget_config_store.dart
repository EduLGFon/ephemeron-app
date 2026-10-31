// Per-widget configuration: lets users bind a widget instance to a specific
// list, note, countdown, tag, habit, or parent task. Stored in
// SharedPreferences under widget_config_<provider> as a string id, or empty
// when unconfigured (binder falls back to generic behavior).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Providers whose widget can be bound to a user-selected entity. The value
/// is the config key suffix stored in SharedPreferences.
const Map<String, String> widgetConfigKinds = <String, String>{
  'PendingTasksWidgetProvider': 'listId',
  'TasksDueTodayWidgetProvider': 'listId',
  'InboxTasksWidgetProvider': 'listId',
  'TagTasksWidgetProvider': 'tag',
  'SmartListWidgetProvider': 'smartListId',
  'SubtaskProgressWidgetProvider': 'taskId',
  'OneNoteWidgetProvider': 'noteId',
  'PinnedNoteWidgetProvider': 'noteId',
  'CountdownWidgetProvider': 'countdownId',
  'HabitStreakWidgetProvider': 'habitId',
  'MatrixWidgetProvider': 'listId',
};

String _configKey(String provider) => 'widget_config_$provider';

class WidgetConfigStore {
  WidgetConfigStore(this._prefs);
  final SharedPreferences _prefs;

  String? get(String provider) {
    final v = _prefs.getString(_configKey(provider));
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String provider, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_configKey(provider));
    } else {
      await _prefs.setString(_configKey(provider), value);
    }
  }

  Future<void> clear(String provider) async {
    await _prefs.remove(_configKey(provider));
  }
}

final widgetConfigStoreProvider = FutureProvider<WidgetConfigStore>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  return WidgetConfigStore(prefs);
});
