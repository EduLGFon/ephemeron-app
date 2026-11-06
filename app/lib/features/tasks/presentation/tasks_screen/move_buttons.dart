part of '../tasks_screen.dart';

/// Move-to-list button with 6 s undo. Restores the previous list on undo.
class _MoveButtons extends ConsumerWidget {
  const _MoveButtons({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = task.listId == null
        ? null
        : ref.watch(taskListsByIdProvider)[task.listId];
    final isMs = isMicrosoftTask(
      taskMicrosoftAccount: task.microsoftAccount,
      listMicrosoftAccount: list?.microsoftAccount,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: 'Move to list',
          onPressed: isMs ? null : () => _move(context, ref),
        ),
        if (task.rrule != null && task.rrule!.isNotEmpty && !isMs)
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
