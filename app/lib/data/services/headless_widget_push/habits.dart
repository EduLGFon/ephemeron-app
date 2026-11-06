part of '../headless_widget_push.dart';

/// Re-reads habits and pushes habit widgets.
Future<void> pushHabitWidgets(AppDatabase db) async {
  try {
    final habits = await HabitRepository(db).watchHabits(archived: false).first;
    await _push(
      'habits_today',
      'HabitsTodayWidgetProvider',
      'Habits today',
      habits.isEmpty ? 'No habits.' : '${habits.length} habits tracked',
    );
    try {
      final items = habits
          .map(
            (h) => '{"id":"${h.id}","title":"${h.name.replaceAll('"', '')}"}',
          )
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'habits_today_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'habits_today_collection_title',
        'Habits today',
      );
      await HomeWidget.updateWidget(
        androidName: 'HabitsTodayCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.HabitsTodayCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
}
