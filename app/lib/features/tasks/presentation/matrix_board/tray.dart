part of '../matrix_board.dart';

class _UnclassifiedTray extends StatelessWidget {
  const _UnclassifiedTray({required this.tasks, required this.dragEnabled});

  final List<Task> tasks;
  final bool dragEnabled;

  @override
  Widget build(BuildContext context) {
    if (!dragEnabled) return _buildCard(context, hovering: false);
    return _DropZone(
      priority: 0,
      builder: (context, hovering) => _buildCard(context, hovering: hovering),
    );
  }

  Widget _buildCard(BuildContext context, {required bool hovering}) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('matrix-unclassified'),
      margin: EdgeInsets.zero,
      color: hovering ? theme.colorScheme.primaryContainer : null,
      shape: _dropShape(theme, hovering),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Unclassified',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${tasks.length}',
                  key: const ValueKey('matrix-count-unclassified'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No unclassified tasks',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final task in tasks)
                MatrixTaskRow(task: task, draggable: dragEnabled),
          ],
        ),
      ),
    );
  }
}
