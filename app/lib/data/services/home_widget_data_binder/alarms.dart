part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderAlarms on HomeWidgetDataBinder {
  Future<void> _refreshAlarms() async {
    try {
      final repo = ref.read(alarmRepositoryProvider);
      final upcoming = await repo.watchUpcoming().first;
      if (upcoming.isEmpty) {
        await _svc.updateByPrefix(
          keyPrefix: 'next_alarm',
          title: 'Alarm',
          body: 'No alarms.',
        );
        return;
      }
      final a = upcoming.first;
      await _svc.updateByPrefix(
        keyPrefix: 'next_alarm',
        title: a.title,
        body: 'Next alarm',
      );
      _mark('next_alarm');
    } catch (_) {}
  }
}
