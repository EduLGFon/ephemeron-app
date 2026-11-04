// Task-list management: rename, recolor and delete lists, with per-list task
// counts and ownership labels. Deleting always asks what happens to tasks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/empty_state.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../application/tasks_providers.dart';
import 'task_list_dialogs.dart';

class TaskListsScreen extends ConsumerWidget {
  const TaskListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(taskListsProvider);
    final tasksAsync = ref.watch(openTasksProvider(null));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage lists'),
        actions: [
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
          return RepaintBoundary(
            child: ListView.separated(
              itemCount: lists.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final list = lists[index];
                final count = counts[list.id] ?? 0;
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
                      Text(
                        count == 1 ? '1 active task' : '$count active tasks',
                      ),
                    ],
                  ),
                  onTap: () => showEditTaskListSheet(context, ref, list),
                  trailing: PopupMenuButton<_ListAction>(
                    tooltip: 'List actions',
                    onSelected: (action) =>
                        _onAction(context, ref, list, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ListAction.rename,
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: _ListAction.color,
                        child: Text('Change color'),
                      ),
                      PopupMenuItem(
                        value: _ListAction.delete,
                        child: Text('Delete list'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
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

enum _ListAction { rename, color, delete }
