// Tasks screen: list filter, overdue section, swipe actions with undo,
// trash, completed view, quick add FAB.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';

import 'package:ephemeron/core/ui/empty_state.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/sources/source_label.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/application/pending_operations.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/tasks_providers.dart';
import 'quick_add_sheet.dart';
import 'smart_list_editor_sheet.dart';
import 'smart_lists_screen.dart';
import 'task_editor_sheet.dart';
import 'task_list_dialogs.dart';
import 'task_lists_screen.dart';
import 'task_source_picker.dart';
import 'trash_screen.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  Future<void> _select(WidgetRef ref, String? id) async {
    ref.read(selectedTaskListProvider.notifier).select(id);
    ref.read(selectedSmartListProvider.notifier).select(null);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSelectedTaskListId(id);
    } catch (_) {}
  }

  Future<void> _selectSmart(WidgetRef ref, String id) async {
    ref.read(selectedSmartListProvider.notifier).select(id);
    ref.read(selectedTaskListProvider.notifier).select(null);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSelectedTaskListId(null);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listId = ref.watch(selectedTaskListProvider);
    final selectedSmartId = ref.watch(selectedSmartListProvider);
    final smartLists =
        ref.watch(smartListsProvider).value ?? const <SmartList>[];
    final smart = selectedSmartId == null
        ? null
        : smartLists.where((s) => s.id == selectedSmartId).firstOrNull;
    final tasksAsync = smart == null
        ? ref.watch(openTasksProvider(listId))
        : ref.watch(smartListTasksProvider(smart));
    final listsAsync = ref.watch(taskListsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const SyncTitle(text: 'Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Completed',
            onPressed: () => _showCompleted(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
            ),
          ),
          PopupMenuButton<_TasksAction>(
            tooltip: 'Task organization',
            onSelected: (action) {
              switch (action) {
                case _TasksAction.manageLists:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TaskListsScreen(),
                    ),
                  );
                case _TasksAction.manageSmartLists:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SmartListsScreen(),
                    ),
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _TasksAction.manageLists,
                child: Text('Manage lists'),
              ),
              PopupMenuItem(
                value: _TasksAction.manageSmartLists,
                child: Text('Manage smart lists'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          listsAsync.maybeWhen(
            data: (lists) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: smart == null && listId == null,
                    onSelected: (_) => _select(ref, null),
                  ),
                  const SizedBox(width: 8),
                  for (final l in lists) ...[
                    GestureDetector(
                      onLongPress: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TaskListsScreen(),
                        ),
                      ),
                      child: Tooltip(
                        message:
                            taskListAccountLabel(l) ??
                            (l.remoteId == null ? localSourceLabel : 'Google'),
                        child: ChoiceChip(
                          avatar: TaskListColorDot(list: l, size: 10),
                          label: Text(l.name),
                          selected: smart == null && listId == l.id,
                          onSelected: (_) => _select(ref, l.id),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final s in smartLists) ...[
                    _SmartListChip(
                      smartList: s,
                      selected: smart?.id == s.id,
                      onSelected: () => _selectSmart(ref, s.id),
                      onLongPress: () => _smartActions(context, ref, s),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ActionChip(
                    label: const Text('+ List'),
                    onPressed: () => showCreateTaskListDialog(context, ref),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('+ Smart list'),
                    onPressed: () => showSmartListEditor(context),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'Could not load tasks.',
                onRetry: () {
                  if (smart == null) {
                    ref.invalidate(openTasksProvider(listId));
                  } else {
                    ref.invalidate(smartListTasksProvider(smart));
                  }
                },
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  if (smart != null) {
                    return EmptyState(
                      icon: Icons.filter_alt_off,
                      title: 'No tasks match',
                      subtitle: 'Nothing matches "${smart.name}" right now.',
                      actionLabel: 'Edit smart list',
                      onAction: () =>
                          showSmartListEditor(context, smartList: smart),
                    );
                  }
                  return EmptyState(
                    icon: Icons.checklist_outlined,
                    title: 'No tasks here',
                    actionLabel: 'Add a task',
                    onAction: () => showQuickAdd(context),
                  );
                }
                final today = _today();
                final overdue = tasks
                    .where(
                      (t) =>
                          t.dueDate != null && t.dueDate!.compareTo(today) < 0,
                    )
                    .toList();
                final overdueIds = overdue.map((t) => t.id).toSet();
                final rest = tasks
                    .where((t) => !overdueIds.contains(t.id))
                    .toList();
                final items = <Widget>[];
                if (overdue.isNotEmpty) {
                  items.add(
                    ListTile(
                      title: Text('Overdue (${overdue.length})'),
                      trailing: TextButton(
                        onPressed: () => _rescheduleAll(context, ref, overdue),
                        child: const Text('Reschedule to today'),
                      ),
                    ),
                  );
                  items.addAll(
                    overdue.map((t) => _TaskTile(task: t, overdue: true)),
                  );
                }
                items.addAll(rest.map((t) => _TaskTile(task: t)));
                return RepaintBoundary(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => items[i],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'tasksFab',
        onPressed: () => showQuickAdd(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _smartActions(
    BuildContext context,
    WidgetRef ref,
    SmartList smart,
  ) async {
    final action = await showModalBottomSheet<_SmartAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit smart list'),
              onTap: () => Navigator.of(ctx).pop(_SmartAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete smart list'),
              onTap: () => Navigator.of(ctx).pop(_SmartAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == _SmartAction.edit) {
      await showSmartListEditor(context, smartList: smart);
      return;
    }
    await ref.read(taskRepositoryProvider).deleteSmartList(smart.id);
    if (ref.read(selectedSmartListProvider) == smart.id) {
      ref.read(selectedSmartListProvider.notifier).select(null);
    }
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _rescheduleAll(
    BuildContext context,
    WidgetRef ref,
    List<Task> overdue,
  ) async {
    final repo = ref.read(taskRepositoryProvider);
    final today = _today();
    for (final t in overdue) {
      await repo.updateTask(t.id, dueDate: () => today);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rescheduled ${overdue.length} tasks')),
      );
    }
  }

  void _showCompleted(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _CompletedScreen()));
  }
}

enum _TasksAction { manageLists, manageSmartLists }

enum _SmartAction { edit, delete }

class _SmartListChip extends ConsumerWidget {
  const _SmartListChip({
    required this.smartList,
    required this.selected,
    required this.onSelected,
    required this.onLongPress,
  });

  final SmartList smartList;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(smartListTasksProvider(smartList));
    final count = results.maybeWhen(
      data: (tasks) => tasks.length,
      orElse: () => null,
    );
    return GestureDetector(
      onLongPress: onLongPress,
      child: ChoiceChip(
        avatar: const Icon(Icons.filter_alt_outlined, size: 16),
        label: Text(
          count == null ? smartList.name : '${smartList.name} ($count)',
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, this.overdue = false});

  final Task task;
  final bool overdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = task.listId == null
        ? null
        : ref.watch(taskListsByIdProvider)[task.listId];
    final source = sourceLabel(
      name: list?.name,
      account: task.googleAccount,
      fallbackAccount: list?.googleAccount,
    );
    return Dismissible(
      key: ValueKey(task.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (dir) async {
        final repo = ref.read(taskRepositoryProvider);
        if (dir == DismissDirection.startToEnd) {
          await repo.completeTask(task.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Completed "${task.title}"'),
                duration: const Duration(seconds: 6),
                persist: false,
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repo.uncompleteTask(task.id),
                ),
              ),
            );
          }
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        final pending = ref.read(pendingOperationsProvider);
        final opId = await pending.scheduleTaskDelete(task.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${task.title}"'),
              duration: const Duration(seconds: 6),
              persist: false,
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => pending.cancel(opId),
              ),
            ),
          );
        }
      },
      child: ListTile(
        leading: Checkbox(
          value: false,
          onChanged: (_) async {
            final repo = ref.read(taskRepositoryProvider);
            await repo.completeTask(task.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Completed "${task.title}"'),
                  duration: const Duration(seconds: 6),
                  persist: false,
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () => repo.uncompleteTask(task.id),
                  ),
                ),
              );
            }
          },
        ),
        title: Text(
          task.title,
          style: overdue ? const TextStyle(color: Colors.red) : null,
        ),
        subtitle: _subtitle(context, ref, source),
        trailing: _MoveButtons(task: task),
        onTap: () => showTaskEditor(context, task: task),
      ),
    );
  }

  Widget? _subtitle(BuildContext context, WidgetRef ref, String? source) {
    final parts = <String>[];
    if (task.dueDate != null) {
      try {
        parts.add(
          DeviceDateFormat.yMMMd(context).format(DateTime.parse(task.dueDate!)),
        );
      } catch (_) {
        parts.add(task.dueDate!);
      }
    }
    if (task.priority > 0) parts.add('P${5 - task.priority}');
    if (task.wontDo) parts.add("Won't do");
    if (source == null && parts.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => pickAndMoveTask(
                context,
                ref,
                taskId: task.id,
                currentListId: task.listId,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        if (parts.isNotEmpty) Text(parts.join('  ')),
      ],
    );
  }
}

/// Move-to-list button with 6 s undo. Restores the previous list on undo.
class _MoveButtons extends ConsumerWidget {
  const _MoveButtons({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: 'Move to list',
          onPressed: () => _move(context, ref),
        ),
        if (task.rrule != null && task.rrule!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Skip occurrence',
            onPressed: () =>
                ref.read(taskRepositoryProvider).skipOccurrence(task.id),
          ),
      ],
    );
  }

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final lists = ref.read(taskListsProvider).value ?? const <TaskList>[];
    final target = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to list'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop('__none__'),
            child: const Text('(no list)'),
          ),
          for (final l in lists)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(l.id),
              child: Text(l.name),
            ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    final repo = ref.read(taskRepositoryProvider);
    final prev = await repo.moveTasks([
      task.id,
    ], target == '__none__' ? null : target);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved "${task.title}"'),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final r = ref.read(taskRepositoryProvider);
            for (final e in prev.entries) {
              await r.moveTasks([e.key], e.value);
            }
          },
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CompletedScreen extends ConsumerWidget {
  const _CompletedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listId = ref.watch(selectedTaskListProvider);
    final completedAsync = ref.watch(completedProvider(listId));
    return Scaffold(
      appBar: AppBar(title: const Text('Completed')),
      body: completedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 48),
                  SizedBox(height: 8),
                  Text('Nothing completed yet'),
                ],
              ),
            );
          }
          final listsById = ref.watch(taskListsByIdProvider);
          return RepaintBoundary(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, i) {
                final t = tasks[i];
                final list = t.listId == null ? null : listsById[t.listId];
                final source = sourceLabel(
                  name: list?.name,
                  account: t.googleAccount,
                  fallbackAccount: list?.googleAccount,
                );
                return ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(t.title),
                  subtitle: (source == null && t.dueDate == null)
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (source != null)
                              InkWell(
                                onTap: () => pickAndMoveTask(
                                  context,
                                  ref,
                                  taskId: t.id,
                                  currentListId: t.listId,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(source)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.swap_horiz, size: 14),
                                  ],
                                ),
                              ),
                            if (t.dueDate != null)
                              Text(
                                DeviceDateFormat.dateIso(context, t.dueDate!),
                              ),
                          ],
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Reopen',
                    onPressed: () =>
                        ref.read(taskRepositoryProvider).uncompleteTask(t.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
