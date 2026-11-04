// Responsive 2x2 matrix board: four equal fields plus a separate tray for
// tasks that no field claims. Task rows open the editor on tap.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';

import '../../../data/drift/app_database.dart';
import 'task_editor_sheet.dart';

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

class MatrixBoard extends StatelessWidget {
  const MatrixBoard({
    super.key,
    required this.fields,
    required this.unclassified,
  });

  final List<MatrixBoardField> fields;
  final List<Task> unclassified;

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
                            Expanded(child: _MatrixField(fields[0])),
                            const SizedBox(width: _gap),
                            Expanded(child: _MatrixField(fields[1])),
                          ],
                        ),
                      ),
                      const SizedBox(height: _gap),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _MatrixField(fields[2])),
                            const SizedBox(width: _gap),
                            Expanded(child: _MatrixField(fields[3])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _UnclassifiedTray(tasks: unclassified),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MatrixField extends StatelessWidget {
  const _MatrixField(this.field);

  final MatrixBoardField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('matrix-field-${field.id}'),
      margin: EdgeInsets.zero,
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
                      itemBuilder: (context, index) =>
                          _MatrixTaskRow(task: field.tasks[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnclassifiedTray extends StatelessWidget {
  const _UnclassifiedTray({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('matrix-unclassified'),
      margin: EdgeInsets.zero,
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
              for (final task in tasks) _MatrixTaskRow(task: task),
          ],
        ),
      ),
    );
  }
}

class _MatrixTaskRow extends StatelessWidget {
  const _MatrixTaskRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('matrix-task-${task.id}'),
      borderRadius: BorderRadius.circular(6),
      onTap: () => showTaskEditor(context, task: task),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
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
    );
  }
}
