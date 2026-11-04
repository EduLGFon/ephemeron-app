// GENERATED CODE - DO NOT MODIFY BY HAND.
// Run: dart run tools/gen_test_runner.dart
//
// One entrypoint for every case file. Flutter compiles one kernel per
// test file, so keeping the suite in a single file removes that cost.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'cases/alarm_repository_case.dart' as alarm_repository;
import 'cases/alarm_window_case.dart' as alarm_window;
import 'cases/app_lock_case.dart' as app_lock;
import 'cases/auth_screen_case.dart' as auth_screen;
import 'cases/backend_auth_case.dart' as backend_auth;
import 'cases/backend_sync_case.dart' as backend_sync;
import 'cases/backup_case.dart' as backup;
import 'cases/calendar_color_case.dart' as calendar_color;
import 'cases/calendar_perf_case.dart' as calendar_perf;
import 'cases/calendar_swipe_case.dart' as calendar_swipe;
import 'cases/countdowns_screen_case.dart' as countdowns_screen;
import 'cases/db_case.dart' as db;
import 'cases/event_rsvp_case.dart' as event_rsvp;
import 'cases/event_scope_case.dart' as event_scope;
import 'cases/focus_screen_case.dart' as focus_screen;
import 'cases/habit_focus_case.dart' as habit_focus;
import 'cases/habit_streak_case.dart' as habit_streak;
import 'cases/habits_screen_case.dart' as habits_screen;
import 'cases/headless_widget_push_case.dart' as headless_widget_push;
import 'cases/home_widget_binder_case.dart' as home_widget_binder;
import 'cases/home_widget_callback_case.dart' as home_widget_callback;
import 'cases/home_widget_case.dart' as home_widget;
import 'cases/l10n_case.dart' as l10n;
import 'cases/month_view_case.dart' as month_view;
import 'cases/note_repository_case.dart' as note_repository;
import 'cases/occurrence_cache_case.dart' as occurrence_cache;
import 'cases/onboarding_case.dart' as onboarding;
import 'cases/parser_case.dart' as parser;
import 'cases/quick_add_case.dart' as quick_add;
import 'cases/recurrence_case.dart' as recurrence;
import 'cases/search_case.dart' as search;
import 'cases/session_restore_case.dart' as session_restore;
import 'cases/settings_case.dart' as settings;
import 'cases/sync_engine_case.dart' as sync_engine;
import 'cases/task_repository_case.dart' as task_repository;
import 'cases/timeline_layout_case.dart' as timeline_layout;
import 'cases/timeline_view_case.dart' as timeline_view;
import 'cases/week_calendar_case.dart' as week_calendar;
import 'cases/widget_case.dart' as widget;
import 'cases/widget_config_case.dart' as widget_config;
import 'cases/widget_image_case.dart' as widget_image;

const _included = <String>{
  'alarm_repository_case.dart',
  'alarm_window_case.dart',
  'app_lock_case.dart',
  'auth_screen_case.dart',
  'backend_auth_case.dart',
  'backend_sync_case.dart',
  'backup_case.dart',
  'calendar_color_case.dart',
  'calendar_perf_case.dart',
  'calendar_swipe_case.dart',
  'countdowns_screen_case.dart',
  'db_case.dart',
  'event_rsvp_case.dart',
  'event_scope_case.dart',
  'focus_screen_case.dart',
  'habit_focus_case.dart',
  'habit_streak_case.dart',
  'habits_screen_case.dart',
  'headless_widget_push_case.dart',
  'home_widget_binder_case.dart',
  'home_widget_callback_case.dart',
  'home_widget_case.dart',
  'l10n_case.dart',
  'month_view_case.dart',
  'note_repository_case.dart',
  'occurrence_cache_case.dart',
  'onboarding_case.dart',
  'parser_case.dart',
  'quick_add_case.dart',
  'recurrence_case.dart',
  'search_case.dart',
  'session_restore_case.dart',
  'settings_case.dart',
  'sync_engine_case.dart',
  'task_repository_case.dart',
  'timeline_layout_case.dart',
  'timeline_view_case.dart',
  'week_calendar_case.dart',
  'widget_case.dart',
  'widget_config_case.dart',
  'widget_image_case.dart',
};

void main() {
  test('test runner includes every case file', () {
    expect(
      _caseFilesOnDisk(),
      _included,
      reason:
          'test/all_test.dart is stale. Run: '
          'dart run tools/gen_test_runner.dart',
    );
  });

  group('alarm_repository', alarm_repository.main);
  group('alarm_window', alarm_window.main);
  group('app_lock', app_lock.main);
  group('auth_screen', auth_screen.main);
  group('backend_auth', backend_auth.main);
  group('backend_sync', backend_sync.main);
  group('backup', backup.main);
  group('calendar_color', calendar_color.main);
  group('calendar_perf', calendar_perf.main);
  group('calendar_swipe', calendar_swipe.main);
  group('countdowns_screen', countdowns_screen.main);
  group('db', db.main);
  group('event_rsvp', event_rsvp.main);
  group('event_scope', event_scope.main);
  group('focus_screen', focus_screen.main);
  group('habit_focus', habit_focus.main);
  group('habit_streak', habit_streak.main);
  group('habits_screen', habits_screen.main);
  group('headless_widget_push', headless_widget_push.main);
  group('home_widget_binder', home_widget_binder.main);
  group('home_widget_callback', home_widget_callback.main);
  group('home_widget', home_widget.main);
  group('l10n', l10n.main);
  group('month_view', month_view.main);
  group('note_repository', note_repository.main);
  group('occurrence_cache', occurrence_cache.main);
  group('onboarding', onboarding.main);
  group('parser', parser.main);
  group('quick_add', quick_add.main);
  group('recurrence', recurrence.main);
  group('search', search.main);
  group('session_restore', session_restore.main);
  group('settings', settings.main);
  group('sync_engine', sync_engine.main);
  group('task_repository', task_repository.main);
  group('timeline_layout', timeline_layout.main);
  group('timeline_view', timeline_view.main);
  group('week_calendar', week_calendar.main);
  group('widget', widget.main);
  group('widget_config', widget_config.main);
  group('widget_image', widget_image.main);
}

Set<String> _caseFilesOnDisk() {
  final cases = Directory('test/cases')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((name) => name.endsWith('_case.dart'))
      .toSet();
  final stray = Directory('test')
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((path) => path.endsWith('_test.dart'))
      .where((path) => !path.endsWith('/all_test.dart'))
      .toSet();
  expect(
    stray,
    isEmpty,
    reason:
        'Move top-level test files under test/cases/ as '
        '*_case.dart and regenerate this runner.',
  );
  return cases;
}
