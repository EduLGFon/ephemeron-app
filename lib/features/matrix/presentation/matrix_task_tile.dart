import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../../quick_add/application/quick_add_provider.dart';
import '../domain/matrix_quadrant.dart';

class MatrixTaskTile extends ConsumerWidget {
  const MatrixTaskTile({
    super.key,
    required this.task,
    required this.quadrant,
    required this.palette,
    required this.onAlarmTap,
  });

  final Task task;
  final MatrixQuadrant quadrant;
  final AppPalette palette;
  final void Function(Task) onAlarmTap;

  String _formatDue(DateTime due, bool hasTime) {
    final localDue = due.toLocal();
    final date =
        '${localDue.year}-${localDue.month.toString().padLeft(2, '0')}-'
        '${localDue.day.toString().padLeft(2, '0')}';
    if (!hasTime) return date;
    return '$date ${localDue.hour.toString().padLeft(2, '0')}:'
        '${localDue.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = quadrant.color;
    final isLate = !task.isCompleted &&
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now());
    final titleColor = isLate
        ? Colors.redAccent
        : (task.isCompleted
            ? palette.text.withValues(alpha: 0.5)
            : palette.text);
    final dueDateColor =
        isLate ? Colors.redAccent : palette.text.withValues(alpha: 0.5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            final repo = ref.read(taskRepositoryProvider);
            if (task.isCompleted) {
              repo.uncompleteTask(task.id);
            } else {
              repo.completeTask(task.id);
            }
          },
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 1, right: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: task.isCompleted
                    ? palette.text.withValues(alpha: 0.5)
                    : (isLate
                        ? Colors.redAccent
                        : color.withValues(alpha: 0.8)),
                width: 1.5,
              ),
              color: task.isCompleted
                  ? palette.text.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
            child: task.isCompleted
                ? Icon(Icons.check, size: 10, color: palette.background)
                : null,
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => ref.read(quickAddProvider.notifier).expand(task),
            onLongPress: () => onAlarmTap(task),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 13,
                    fontWeight: isLate ? FontWeight.bold : FontWeight.normal,
                    decoration:
                        task.isCompleted ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (task.dueDate != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Row(
                      children: [
                        Icon(
                          isLate
                              ? Icons.warning_amber_rounded
                              : Icons.calendar_today,
                          size: 10,
                          color: dueDateColor,
                        ),
                        const SizedBox(width: 4),
                        if (task.alarmPreset != null) ...[
                          GestureDetector(
                            onTap: () => onAlarmTap(task),
                            child: Icon(Icons.alarm,
                                size: 10, color: dueDateColor),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          _formatDue(task.dueDate!, task.dueHasTime),
                          style: TextStyle(
                            color: dueDateColor,
                            fontSize: 10,
                            fontWeight:
                                isLate ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
