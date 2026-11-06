part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderTasks on HomeWidgetDataBinder {
  Future<void> _refreshTasks() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final listId = await _config('PendingTasksWidgetProvider');
      final tasks = await repo.watchOpen(listId: listId).first;
      final titles = tasks.take(5).map((t) => t.title).toList();
      await _svc.update(
        keyPrefix: 'pending_tasks',
        provider: 'PendingTasksWidgetProvider',
        title: 'Pending tasks',
        body: titles.isEmpty ? 'No pending tasks.' : titles.join('\n'),
      );
      _mark('pending_tasks');
      _mark('pending_tasks_collection');
      await _svc.updateCollection(
        keyPrefix: 'pending_tasks_collection',
        provider: 'PendingTasksCollectionProvider',
        title: 'Pending tasks',
        items: tasks
            .take(5)
            .map((t) => {'id': t.id, 'title': t.title})
            .toList(),
      );
      _mark('pending_tasks_collection');
    } catch (_) {}
  }

  Future<void> _refreshMatrix() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final listId = await _config('MatrixWidgetProvider');
      final tasks = await repo.watchOpen(listId: listId).first;
      final counts = <String, int>{};
      for (final t in tasks) {
        counts[t.priority.toString()] =
            (counts[t.priority.toString()] ?? 0) + 1;
      }
      await _svc.updateByPrefix(
        keyPrefix: 'matrix',
        title: 'Matrix',
        body: counts.entries.map((e) => 'P${e.key}: ${e.value}').join(' '),
      );
      _mark('matrix');
      final matrixListId = listId;
      if (matrixListId == null) {
        await _svc.updateByPrefix(
          keyPrefix: 'matrix_counts',
          title: 'Matrix',
          body: counts.entries.map((e) => 'P${e.key}: ${e.value}').join(' '),
        );
        _mark('matrix_counts');
      }
    } catch (_) {}
  }

  Future<void> _refreshTaskVariants() async {
    try {
      final repo = ref.read(taskRepositoryProvider);
      final tasks = await repo.watchOpen().first;
      final now = DateTime.now();
      final todayKey =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final dueToday = tasks
          .where((t) => (t.dueDate ?? '') == todayKey)
          .toList();
      final overdue = tasks.where((t) {
        final d = t.dueDate;
        return d != null && d.compareTo(todayKey) < 0;
      }).toList();
      final inbox = tasks.where((t) => t.listId == null).toList();
      await _svc.updateByPrefix(
        keyPrefix: 'tasks_due_today',
        title: 'Due today',
        body: dueToday.isEmpty
            ? 'No tasks due today.'
            : dueToday.map((t) => t.title).join('\n'),
      );
      _mark('tasks_due_today');
      await _svc.updateByPrefix(
        keyPrefix: 'inbox_tasks',
        title: 'Inbox',
        body: inbox.isEmpty ? 'Inbox empty.' : '${inbox.length} tasks',
      );
      _mark('inbox_tasks');
      await _svc.updateByPrefix(
        keyPrefix: 'overdue_badge',
        title: 'Overdue',
        body: '${overdue.length}',
      );
      _mark('overdue_badge');
      await _svc.updateByPrefix(
        keyPrefix: 'task_counts',
        title: 'Tasks',
        body: 'Open: ${tasks.length}',
      );
      _mark('task_counts');
    } catch (_) {}
  }
}
