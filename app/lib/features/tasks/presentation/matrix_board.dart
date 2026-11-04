// Responsive 2x2 matrix board: four equal fields plus a separate tray for
// tasks that no field claims. Task rows open the editor on tap. In priority
// mode rows can be long-pressed and dragged between fields and the tray, and
// every row carries a circular complete checkbox.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/tasks/eisenhower.dart';
import '../application/tasks_providers.dart';
import 'matrix_task_row.dart';

const double _pagePadding = 12;
const double _gap = 8;

class MatrixBoardField {
  const MatrixBoardField({
    required this.id,
    required this.title,
    required this.tasks,
  });

  final String id;
  final String title;
  final List<Task> tasks;
}

/// Priority value stored for a field id: p1 maps to 4 and p4 to 1.
int _dropPriority(String fieldId) => switch (fieldId) {
  'p1' => 4,
  'p2' => 3,
  'p3' => 2,
  'p4' => 1,
  _ => 0,
};

ShapeBorder? _dropShape(ThemeData theme, bool hovering) => hovering
    ? RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary, width: 2),
      )
    : null;

class MatrixBoard extends StatelessWidget {
  const MatrixBoard({
    super.key,
    required this.fields,
    required this.unclassified,
    required this.mode,
  });

  final List<MatrixBoardField> fields;
  final List<Task> unclassified;
  final MatrixMode mode;

  bool get _dragEnabled => mode == MatrixMode.priority;

  Widget _field(int index) => _MatrixField(
    fields[index],
    dragEnabled: _dragEnabled,
    dropPriority: _dropPriority(fields[index].id),
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final boardWidth = constraints.maxWidth - _pagePadding * 2;
          final cellWidth = (boardWidth - _gap) / 2;
          final cellHeight = math.min(math.max(cellWidth * 1.1, 150), 280);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              _pagePadding,
              _pagePadding,
              _pagePadding,
              88,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: cellHeight * 2 + _gap,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _field(0)),
                            const SizedBox(width: _gap),
                            Expanded(child: _field(1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: _gap),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _field(2)),
                            const SizedBox(width: _gap),
                            Expanded(child: _field(3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _UnclassifiedTray(
                  tasks: unclassified,
                  dragEnabled: _dragEnabled,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MatrixField extends StatelessWidget {
  const _MatrixField(
    this.field, {
    required this.dragEnabled,
    required this.dropPriority,
  });

  final MatrixBoardField field;
  final bool dragEnabled;
  final int dropPriority;

  @override
  Widget build(BuildContext context) {
    if (!dragEnabled) return _buildCard(context, hovering: false);
    return _DropZone(
      priority: dropPriority,
      builder: (context, hovering) => _buildCard(context, hovering: hovering),
    );
  }

  Widget _buildCard(BuildContext context, {required bool hovering}) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('matrix-field-${field.id}'),
      margin: EdgeInsets.zero,
      color: hovering ? theme.colorScheme.primaryContainer : null,
      shape: _dropShape(theme, hovering),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    field.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${field.tasks.length}',
                  key: ValueKey('matrix-count-${field.id}'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: field.tasks.isEmpty
                  ? Center(
                      child: Text(
                        'Empty',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: field.tasks.length,
                      itemBuilder: (context, index) => MatrixTaskRow(
                        task: field.tasks[index],
                        draggable: dragEnabled,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Accepts task drops for a stored priority (0 is the unclassified tray).
class _DropZone extends ConsumerWidget {
  const _DropZone({required this.priority, required this.builder});

  final int priority;
  final Widget Function(BuildContext context, bool hovering) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (details) => details.data.priority != priority,
      onAcceptWithDetails: (details) async {
        final task = details.data;
        if (task.priority == priority) return;
        await ref
            .read(taskRepositoryProvider)
            .updateTask(task.id, priority: priority);
      },
      builder: (context, candidateData, rejectedData) =>
          builder(context, candidateData.isNotEmpty),
    );
  }
}
