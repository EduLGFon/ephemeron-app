part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderFocus on HomeWidgetDataBinder {
  Future<void> _refreshFocus() async {
    try {
      final repo = ref.read(focusRepositoryProvider);
      final session = await repo.currentSession();
      final phase = session?.phase == 'break' ? 'break' : 'focus';
      await _svc.updateByPrefix(
        keyPrefix: 'focus_timer',
        title: session == null
            ? 'Focus'
            : (phase == 'break' ? 'On break' : 'Focusing'),
        body: session == null ? 'No active session.' : '$phase session running',
      );
      _mark('focus_timer');
    } catch (_) {}
  }

  Future<void> _refreshDailySummary() async {
    try {
      final taskRepo = ref.read(taskRepositoryProvider);
      final tasks = await taskRepo.watchOpen().first;
      final focusRepo = ref.read(focusRepositoryProvider);
      final minutes = await focusRepo.totalMinutes(
        DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch,
      );
      await _svc.updateByPrefix(
        keyPrefix: 'daily_summary',
        title: 'Today',
        body: 'Open tasks: ${tasks.length}\nFocus: $minutes min',
      );
      _mark('daily_summary');
      await _svc.updateByPrefix(
        keyPrefix: 'focus_minutes',
        title: 'Focus',
        body: '$minutes min (24h)',
      );
      _mark('focus_minutes');
    } catch (_) {}
  }
}
