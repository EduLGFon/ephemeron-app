part of '../task_list_dialogs.dart';

/// Deletion confirmation. Defaults to moving tasks when another list exists;
/// with no other list the only safe action is deleting the tasks too.
Future<void> showDeleteTaskListDialog(
  BuildContext context,
  WidgetRef ref,
  TaskList list,
) async {
  final others = [
    for (final other in ref.read(taskListsProvider).value ?? const <TaskList>[])
      if (other.id != list.id) other,
  ];
  var deleteTasks = others.isEmpty;
  var target = others.isEmpty ? null : others.first.id;
  final decision = await showDialog<_DeleteDecision>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Delete "${list.name}"?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (others.isNotEmpty) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Move tasks'),
                      icon: Icon(Icons.drive_file_move_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('Delete tasks'),
                      icon: Icon(Icons.delete_outline),
                    ),
                  ],
                  selected: {deleteTasks},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => deleteTasks = selection.single),
                ),
                const SizedBox(height: 12),
                if (!deleteTasks)
                  DropdownButtonFormField<String>(
                    initialValue: target,
                    decoration: const InputDecoration(
                      labelText: 'Move tasks to',
                    ),
                    items: [
                      for (final other in others)
                        DropdownMenuItem(
                          value: other.id,
                          child: Text(other.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => target = value),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                deleteTasks
                    ? 'The list is removed. Its tasks go to Trash and stay '
                          'there until you restore or permanently delete them.'
                    : 'Tasks keep their details and move to the selected '
                          'list. The empty list is removed.',
              ),
              if (list.remoteId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'The Google Tasks list is removed on the next sync.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(
              ctx,
            ).pop(_DeleteDecision(deleteTasks: deleteTasks, moveTo: target)),
            child: const Text('Delete list'),
          ),
        ],
      ),
    ),
  );
  if (decision == null) return;
  try {
    await ref
        .read(taskRepositoryProvider)
        .deleteList(
          list.id,
          deleteTasks: decision.deleteTasks,
          moveTasksToListId: decision.moveTo,
        );
  } on SourceMoveException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _DeleteDecision {
  const _DeleteDecision({required this.deleteTasks, required this.moveTo});

  final bool deleteTasks;
  final String? moveTo;
}
