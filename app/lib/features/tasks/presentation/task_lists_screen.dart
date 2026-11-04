// Task-list management: rename, recolor and delete lists, with per-list task
// counts and ownership labels. Deleting always asks what happens to tasks.
// Custom order uses long-press drag and persists only local sortOrder values.
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/empty_state.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../../../domain/tasks/task_sort.dart';
import '../application/task_sorting.dart';
import '../application/tasks_providers.dart';
import 'task_list_dialogs.dart';

class TaskListsScreen extends ConsumerWidget {
  const TaskListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(taskListsProvider);
    final tasksAsync = ref.watch(openTasksProvider(null));
    final sort = ref.watch(taskListSortProvider).value ?? TaskListSort.custom;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage lists'),
        actions: [
          PopupMenuButton<TaskListSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort lists',
            initialValue: sort,
            onSelected: (mode) =>
                ref.read(taskListSortProvider.notifier).select(mode),
            itemBuilder: (_) => [
              for (final mode in TaskListSort.values)
                PopupMenuItem(value: mode, child: Text(mode.label)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New list',
            onPressed: () => showCreateTaskListDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'taskListsFab',
        onPressed: () => showCreateTaskListDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: listsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load lists.')),
        data: (lists) {
          if (lists.isEmpty) {
            return EmptyState(
              icon: Icons.list_alt,
              title: 'No task lists',
              subtitle:
                  'Create a list to group tasks, or use the unlisted '
                  'bucket.',
              actionLabel: 'Create list',
              onAction: () => showCreateTaskListDialog(context, ref),
            );
          }
          final counts = <String, int>{};
          for (final task in tasksAsync.value ?? const <Task>[]) {
            final listId = task.listId;
            if (listId != null) counts[listId] = (counts[listId] ?? 0) + 1;
          }
          final sorted = [...lists]
            ..sort((a, b) => compareTaskLists(a, b, sort));
          Widget tile(TaskList list) =>
              _listTile(context, ref, list, counts[list.id] ?? 0);
          if (sort == TaskListSort.custom) {
            return _ReorderableLists(lists: sorted, itemBuilder: tile);
          }
          return RepaintBoundary(
            child: ListView.separated(
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => tile(sorted[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _listTile(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
    int count,
  ) {
    final source =
        sourceLabel(
          name: list.name,
          account: list.googleAccount,
          isLocal: list.remoteId == null,
        ) ??
        list.name;
    return ListTile(
      leading: TaskListColorDot(list: list, size: 18),
      title: Text(list.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source),
          Text(count == 1 ? '1 active task' : '$count active tasks'),
        ],
      ),
      onTap: () => showEditTaskListSheet(context, ref, list),
      trailing: PopupMenuButton<_ListAction>(
        tooltip: 'List actions',
        onSelected: (action) => _onAction(context, ref, list, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _ListAction.rename, child: Text('Rename')),
          PopupMenuItem(value: _ListAction.color, child: Text('Change color')),
          PopupMenuItem(value: _ListAction.delete, child: Text('Delete list')),
        ],
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
    _ListAction action,
  ) async {
    switch (action) {
      case _ListAction.rename:
      case _ListAction.color:
        await showEditTaskListSheet(context, ref, list);
      case _ListAction.delete:
        await showDeleteTaskListDialog(context, ref, list);
        if (ref.read(selectedTaskListProvider) == list.id) {
          ref.read(selectedTaskListProvider.notifier).select(null);
        }
    }
  }
}

/// Long-press drag ordering for the custom list sort mode.
class _ReorderableLists extends ConsumerStatefulWidget {
  const _ReorderableLists({required this.lists, required this.itemBuilder});

  final List<TaskList> lists;
  final Widget Function(TaskList list) itemBuilder;

  @override
  ConsumerState<_ReorderableLists> createState() => _ReorderableListsState();
}

class _ReorderableListsState extends ConsumerState<_ReorderableLists> {
  late List<TaskList> _lists;

  @override
  void initState() {
    super.initState();
    _lists = [...widget.lists];
  }

  @override
  void didUpdateWidget(covariant _ReorderableLists oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.lists, widget.lists)) {
      _lists = [...widget.lists];
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _lists.removeAt(oldIndex);
      _lists.insert(newIndex, item);
    });
    _persist();
  }

  Future<void> _persist() async {
    try {
      await ref.read(taskRepositoryProvider).reorderLists([
        for (final list in _lists) list.id,
      ]);
    } catch (_) {
      if (mounted) setState(() => _lists = [...widget.lists]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _lists.length,
        onReorderItem: _onReorder,
        itemBuilder: (context, i) {
          final list = _lists[i];
          return ReorderableDelayedDragStartListener(
            key: ValueKey('reorder-list-${list.id}'),
            index: i,
            child: widget.itemBuilder(list),
          );
        },
      ),
    );
  }
}

enum _ListAction { rename, color, delete }
