part of '../matrix_board.dart';

/// Accepts task drops for a stored priority (0 is the unclassified tray).
class _DropZone extends ConsumerWidget {
  const _DropZone({required this.priority, required this.builder});

  final int priority;
  final Widget Function(BuildContext context, bool hovering) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) {
        final task = details.data;
        if (task.priority == priority) return false;
        final lists = ref.read(taskListsByIdProvider);
        final list = task.listId == null ? null : lists[task.listId];
        if (isMicrosoftTask(
          taskMicrosoftAccount: task.microsoftAccount,
          listMicrosoftAccount: list?.microsoftAccount,
        )) {
          return false;
        }
        return true;
      },
      onAcceptWithDetails: (details) async {
        final task = details.data;
        if (task.priority == priority) return;
        final lists = ref.read(taskListsByIdProvider);
        final list = task.listId == null ? null : lists[task.listId];
        if (isMicrosoftTask(
          taskMicrosoftAccount: task.microsoftAccount,
          listMicrosoftAccount: list?.microsoftAccount,
        )) {
          return;
        }
        await ref
            .read(taskRepositoryProvider)
            .updateTask(task.id, priority: priority);
      },
      builder: (context, candidateData, rejectedData) =>
          builder(context, candidateData.isNotEmpty),
    );
  }
}
