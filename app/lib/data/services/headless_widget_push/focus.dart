part of '../headless_widget_push.dart';

Future<void> pushFocusWidgets(AppDatabase db) async {
  try {
    final session = await FocusRepository(db).currentSession();
    await _push(
      'focus_timer',
      'FocusTimerWidgetProvider',
      session == null ? 'Focus' : 'Focusing',
      session == null ? 'No active session.' : 'Session running',
    );
  } catch (_) {}
}
