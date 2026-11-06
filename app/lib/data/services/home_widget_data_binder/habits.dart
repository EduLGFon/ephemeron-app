part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderHabits on HomeWidgetDataBinder {
  Future<void> _refreshHabits() async {
    try {
      final repo = ref.read(habitRepositoryProvider);
      final habits = await repo.watchHabits(archived: false).first;
      await _svc.updateByPrefix(
        keyPrefix: 'habits_today',
        title: 'Habits today',
        body: habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
      );
      _mark('habits_today');
      await _svc.updateCollection(
        keyPrefix: 'habits_today_collection',
        provider: 'HabitsTodayCollectionProvider',
        title: 'Habits today',
        items: habits.map((h) => {'id': h.id, 'title': h.name}).toList(),
      );
      _mark('habits_today_collection');
    } catch (_) {}
  }
}
