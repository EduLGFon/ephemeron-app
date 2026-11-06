part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderCore on HomeWidgetDataBinder {
  Future<void> refreshAll() async {
    _touched.clear();
    await Future.wait([
      _refreshTasks(),
      _refreshCountdowns(),
      _refreshHabits(),
      _refreshNotes(),
      _refreshFocus(),
      _refreshEvents(),
      _refreshWeekCalendar(),
      _refreshMatrix(),
      _refreshAlarms(),
      _refreshTaskVariants(),
      _refreshDailySummary(),
      _refreshSyncStatus(),
      _refreshExtras(),
    ]);
    // Derived last so it can skip keys with dedicated real data.
    await _refreshDerived();
    // Images need a Flutter engine: foreground only, best-effort.
    await _refreshImages();
    // Fill any widget type that has no dedicated wiring yet so pinned
    // widgets are never blank.
    for (final w in homeWidgets) {
      if (_touched.contains(w.keyPrefix)) continue;
      try {
        await _svc.updateByPrefix(
          keyPrefix: w.keyPrefix,
          title: w.keyPrefix.replaceAll('_', ' '),
          body: 'Open ephemeron for details.',
        );
        _mark(w.keyPrefix);
      } catch (_) {}
    }
    try {
      await _svc.updateByPrefix(
        keyPrefix: 'sync_status',
        title: 'Sync status',
        body: 'Updated ${DateTime.now().toLocal()}',
      );
    } catch (_) {}
  }

  Future<String?> _config(String provider) async {
    try {
      final store = await ref.read(widgetConfigStoreProvider.future);
      return store.get(provider);
    } catch (_) {
      return null;
    }
  }
}
