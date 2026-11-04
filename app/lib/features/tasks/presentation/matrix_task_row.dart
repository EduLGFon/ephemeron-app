// Task row for the matrix board. Keeps the complete checkbox and the
// tap-to-edit area in separate gesture regions, and wraps the row in a long
// press draggable only when the board is in priority mode.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ephemeron/core/time/device_date_format.dart';

import '../../../data/drift/app_database.dart';
import '../application/tasks_providers.dart';
import 'task_editor_sheet.dart';

class MatrixTaskRow extends StatelessWidget {
  const MatrixTaskRow({super.key, required this.task, required this.draggable});

  final Task task;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final content = _MatrixTaskRowContent(
      key: ValueKey('matrix-task-${task.id}'),
      task: task,
    );
    if (!draggable) return content;
    return LongPressDraggable<Task>(
      data: task,
      feedback: _TaskDragFeedback(title: task.title),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _MatrixTaskRowContent(task: task),
      ),
      child: content,
    );
  }
}

class _MatrixTaskRowContent extends ConsumerWidget {
  const _MatrixTaskRowContent({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: 'Mark "${task.title}" concluded',
            child: SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                key: ValueKey('matrix-complete-${task.id}'),
                value: false,
                shape: const CircleBorder(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => _complete(context, ref),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => showTaskEditor(context, task: task),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    if (task.dueDate != null)
                      Text(
                        DeviceDateFormat.dateIso(context, task.dueDate!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    await repo.completeTask(task.id);
    if (!context.mounted) return;
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
}

class _TaskDragFeedback extends StatelessWidget {
  const _TaskDragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surfaceContainerHighest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
