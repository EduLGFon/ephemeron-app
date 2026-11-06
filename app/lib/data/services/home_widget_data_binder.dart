import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../domain/habits/date_key.dart';
import '../../../core/power/power_saving_manager.dart';
import '../../../core/time/time.dart';
import '../../../features/tasks/application/tasks_providers.dart';
import '../../../features/countdowns/application/countdowns_providers.dart';
import '../../../features/habits/application/habits_providers.dart';
import '../../../features/notes/application/notes_providers.dart';
import '../../../features/focus/application/focus_providers.dart';
import '../../../features/calendar/application/calendar_providers.dart';
import '../../../features/alarms/application/alarm_providers.dart';
import '../../../features/settings/application/settings_providers.dart';
import 'home_widget_service.dart';
import 'home_widget_support.dart';
import 'week_calendar_data.dart';
import 'week_widget_options.dart';
import 'widget_config_store.dart';
import 'widget_image_service.dart';

part 'home_widget_data_binder/core.dart';
part 'home_widget_data_binder/tasks.dart';
part 'home_widget_data_binder/countdowns.dart';
part 'home_widget_data_binder/habits.dart';
part 'home_widget_data_binder/notes.dart';
part 'home_widget_data_binder/focus.dart';
part 'home_widget_data_binder/calendar.dart';
part 'home_widget_data_binder/alarms.dart';
part 'home_widget_data_binder/sync_extras.dart';
part 'home_widget_data_binder/derived.dart';
part 'home_widget_data_binder/images.dart';

/// True when [className] is [provider] either as an exact short name
/// (e.g. `WeekCalendarWidgetProvider`) or as a fully qualified Android class
/// name ending in `.<provider>` (e.g.
/// `com.spotnik.ephemeron.WeekCalendarWidgetProvider`).
bool widgetProviderMatches(String? className, String provider) {
  if (className == null) return false;
  if (className == provider) return true;
  return className.endsWith('.$provider');
}

class HomeWidgetDataBinder {
  HomeWidgetDataBinder(this.ref);
  final Ref ref;

  HomeWidgetService get _svc => ref.read(homeWidgetServiceProvider);
  final Set<String> _touched = <String>{};

  void _mark(String prefix) => _touched.add(prefix);
}

final homeWidgetDataBinderProvider = Provider<HomeWidgetDataBinder>((ref) {
  return HomeWidgetDataBinder(ref);
});
