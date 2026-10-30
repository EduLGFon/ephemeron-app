// Tasks screen: list filter, overdue section, swipe actions with undo,
// trash, completed view, quick add FAB.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/tasks_providers.dart';
import 'quick_add_sheet.dart';
import 'task_editor_sheet.dart';
import 'trash_screen.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listId = ref.watch(selectedTaskListProvider);
    final tasksAsync = ref.watch(openTasksProvider(listId));
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
                    selected: listId == null,
                    onSelected: (_) => ref
                        .read(selectedTaskListProvider.notifier)
                        .select(null),
                  ),
                  const SizedBox(width: 8),
                  for (final l in lists) ...[
                    ChoiceChip(
                      label: Text(l.name),
                      selected: listId == l.id,
                      onSelected: (_) => ref
                          .read(selectedTaskListProvider.notifier)
                          .select(l.id),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ActionChip(
                    label: const Text('+ List'),
                    onPressed: () => _addList(context, ref),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('+ Smart list'),
                    onPressed: () => _addSmartList(context, ref),
                  ),
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
                onRetry: () => ref.invalidate(openTasksProvider(listId)),
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  return _EmptyState(onAdd: () => showQuickAdd(context));
                }
                final today = _today();
                final overdue = tasks
                    .where(
                      (t) =>
                          t.dueDate != null && t.dueDate!.compareTo(today) < 0,
                    )
                    .toList();
                final rest = tasks.where((t) => !overdue.contains(t)).toList();
                return ListView(
                  children: [
                    if (overdue.isNotEmpty) ...[
                      ListTile(
                        title: Text('Overdue (${overdue.length})'),
                        trailing: TextButton(
                          onPressed: () =>
                              _rescheduleAll(context, ref, overdue),
                          child: const Text('Reschedule to today'),
                        ),
                      ),
                      for (final t in overdue)
                        _TaskTile(task: t, overdue: true),
                    ],
                    for (final t in rest) _TaskTile(task: t),
                  ],
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

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addSmartList(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    bool showCompleted = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New smart list'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              CheckboxListTile(
                value: showCompleted,
                onChanged: (v) => setState(() => showCompleted = v ?? false),
                title: const Text('Include completed'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok == true && name.isNotEmpty) {
      await ref.read(taskRepositoryProvider).createSmartList(name, {
        'showCompleted': showCompleted,
      });
    }
  }

  Future<void> _addList(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(taskRepositoryProvider).createList(name);
    }
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

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, this.overdue = false});

  final Task task;
  final bool overdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final repo = ref.read(taskRepositoryProvider);
        await repo.softDeleteTasks([task.id]);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${task.title}"'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => repo.restoreTasks([task.id]),
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
        subtitle: _subtitle(),
        trailing: _MoveButtons(task: task),
        onTap: () => showTaskEditor(context, task: task),
      ),
    );
  }

  Widget? _subtitle() {
    final parts = <String>[];
    if (task.dueDate != null) parts.add(task.dueDate!);
    if (task.priority > 0) parts.add('P${5 - task.priority}');
    if (task.wontDo) parts.add("Won't do");
    if (parts.isEmpty) return null;
    return Text(parts.join('  '));
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.checklist_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('No tasks here'),
          const SizedBox(height: 8),
          FilledButton(onPressed: onAdd, child: const Text('Add a task')),
        ],
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
            return const Center(child: Text('Nothing completed yet'));
          }
          return ListView(
            children: [
              for (final t in tasks)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(t.title),
                  subtitle: t.dueDate == null ? null : Text(t.dueDate!),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Reopen',
                    onPressed: () =>
                        ref.read(taskRepositoryProvider).uncompleteTask(t.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
