part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderCountdowns on HomeWidgetDataBinder {
  Future<void> _refreshCountdowns() async {
    try {
      final repo = ref.read(countdownRepositoryProvider);
      final all = await repo.watchCountdowns().first;
      final pinnedId = await _config('CountdownWidgetProvider');
      final items = pinnedId == null
          ? all
          : ([
              ...all.where((c) => c.id == pinnedId),
              ...all.where((c) => c.id != pinnedId),
            ]);
      if (items.isEmpty) {
        await _svc.updateByPrefix(
          keyPrefix: 'countdown',
          title: 'Countdown',
          body: 'No countdowns.',
        );
        return;
      }
      final next = items.first;
      final target = DateTime.tryParse(next.targetDate ?? '') ?? DateTime.now();
      final days = target.difference(DateTime.now()).inDays;
      await _svc.updateByPrefix(
        keyPrefix: 'countdown',
        title: next.title,
        body: '$days days remaining',
      );
      _mark('countdown');
      await _svc.updateCollection(
        keyPrefix: 'all_countdowns_collection',
        provider: 'CountdownsCollectionProvider',
        title: 'Countdowns',
        items: items.map((c) => {'id': c.id, 'title': c.title}).toList(),
      );
      _mark('all_countdowns_collection');
    } catch (_) {}
  }
}
