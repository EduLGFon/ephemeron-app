part of '../headless_widget_push.dart';

/// Re-reads open tasks and pushes task widgets. Honors an optional
/// list-id filter.
Future<void> pushTaskWidgets(AppDatabase db, {String? listId}) async {
  try {
    final tasks = await TaskRepository(db).watchOpen(listId: listId).first;
    final titles = tasks.take(5).map((t) => t.title).toList();
    await _push(
      'pending_tasks',
      'PendingTasksWidgetProvider',
      'Pending tasks',
      titles.isEmpty ? 'No pending tasks.' : titles.join('\n'),
    );
    try {
      final items = tasks
          .take(5)
          .map(
            (t) => '{"id":"${t.id}","title":"${t.title.replaceAll('"', '')}"}',
          )
          .join(',');
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_items',
        '[$items]',
      );
      await HomeWidget.saveWidgetData<String>(
        'pending_tasks_collection_title',
        'Pending tasks',
      );
      await HomeWidget.updateWidget(
        androidName: 'PendingTasksCollectionProvider',
        qualifiedAndroidName:
            'com.spotnik.ephemeron.PendingTasksCollectionProvider',
      );
    } catch (_) {}
  } catch (_) {}
}
