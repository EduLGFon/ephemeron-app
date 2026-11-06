// Shared headless widget payload builders. Used both by the WorkManager
// background sync and by the widget toggle callback so a tap is reflected
// without opening the app. No Riverpod: everything runs off [db] directly.
import 'package:drift/drift.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/time/time.dart';
import '../drift/app_database.dart';
import '../repositories/occurrence_repository.dart';
import '../repositories/countdown_repository.dart';
import '../repositories/focus_repository.dart';
import '../repositories/habit_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/task_repository.dart';
import 'week_calendar_data.dart';

export 'alarm_cancel.dart' show cancelAlarmsForEntity;

part 'headless_widget_push/core.dart';
part 'headless_widget_push/tasks.dart';
part 'headless_widget_push/habits.dart';
part 'headless_widget_push/countdowns.dart';
part 'headless_widget_push/notes.dart';
part 'headless_widget_push/focus.dart';
part 'headless_widget_push/occurrence.dart';
part 'headless_widget_push/all.dart';
