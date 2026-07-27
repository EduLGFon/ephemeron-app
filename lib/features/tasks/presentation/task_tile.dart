import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../../core/theme/theme_palettes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/database.dart';
import '../application/task_providers.dart';
import '../../quick_add/application/quick_add_provider.dart';
import '../../../presentation/widgets/confirmation_dialog.dart';
import '../../../presentation/widgets/recurrence_delete_dialog.dart';
import '../domain/task_recurrence.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, required this.palette});

  final Task task;
  final AppPalette palette;

  Color _parseColor(String hex) {
    try {
      final c = hex.replaceAll('#', '');
      return Color(int.parse('FF\$c', radix: 16));
    } catch (_) {
      return const Color(0xFF1B4B4A);
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '\${minutes}m';
    final hours = minutes / 60.0;
    if (hours == hours.toInt()) {
      return '\${hours.toInt()}h';
    }
    return '\${hours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(taskRepositoryProvider);
    final priorityColor = switch (task.priority) {
      3 => AppColors.priorityHigh,
      2 => AppColors.priorityMedium,
      1 => AppColors.priorityLow,
      _ => palette.text.withValues(alpha: 0.2),
    };

    final isLate = !task.isCompleted &&
        task.dueDate != null &&
        task.dueDate!.isBefore(DateTime.now());
    final dueDateColor =
        isLate ? Colors.redAccent : palette.text.withValues(alpha: 0.5);

    final tagsAsync = ref.watch(taskTagsProvider(task.id));
    final tags = tagsAsync.value ?? [];

    Color borderColor = palette.text.withValues(alpha: 0.05);
    double borderWidth = 1.0;
    if (tags.isNotEmpty && !isLate) {
      borderColor = _parseColor(tags.first.colorHex);
      borderWidth = 2.0;
    }

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade900,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final recurrence = TaskRecurrence.decode(task.recurrenceRule);
        if (recurrence.isRecurring) {
          final choice = await showRecurrenceDeleteDialog(
            context: context,
            ref: ref,
            title: 'Delete Recurring Task?',
          );
          if (choice == null) return false;

          if (choice == RecurrenceDeleteType.onlyThis) {
            final nextDue = recurrence.nextOccurrence(task.dueDate!);
            if (nextDue != null) {
              await repo.updateTask(task.id, dueDate: Value(nextDue));
            }
            return false;
          } else {
            return true;
          }
        } else {
          return await showConfirmationDialog(
            context: context,
            ref: ref,
            title: 'Delete Task?',
            content:
                'Are you sure you want to delete this task? It will be moved to Trash.',
            confirmLabel: 'Delete',
            isDestructive: true,
          );
        }
      },
      onDismissed: (_) => repo.softDeleteTask(task.id),
      child: Container(
        decoration: BoxDecoration(
          color:
              palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: GestureDetector(
                onTap: () {
                  if (task.isWontDo) {
                    repo.toggleWontDo(task.id);
                  } else {
                    if (task.isCompleted) {
                      repo.uncompleteTask(task.id);
                    } else {
                      repo.completeTask(task.id);
                    }
                  }
                },
                child: task.isWontDo
                    ? Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent.withValues(alpha: 0.2),
                        ),
                        child: const Icon(Icons.block,
                            size: 16, color: Colors.redAccent),
                      )
                    : Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: task.isCompleted
                                ? palette.text.withValues(alpha: 0.3)
                                : priorityColor,
                            width: 2,
                          ),
                          color: task.isCompleted
                              ? palette.text.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                        child: task.isCompleted
                            ? Icon(Icons.check,
                                size: 16, color: palette.background)
                            : null,
                      ),
              ),
              title: Text(
                task.title,
                style: TextStyle(
                  color: task.isCompleted
                      ? palette.text.withValues(alpha: 0.4)
                      : task.isWontDo
                          ? palette.text.withValues(alpha: 0.45)
                          : palette.text,
                  fontWeight: FontWeight.w600,
                  decoration: (task.isCompleted || task.isWontDo)
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: palette.text.withValues(alpha: 0.45),
                ),
              ),
              subtitle: (task.dueDate != null || task.durationMinutes != 30)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          if (task.dueDate != null) ...[
                            Icon(
                              isLate
                                  ? Icons.warning_amber_rounded
                                  : Icons.calendar_today,
                              size: 12,
                              color: dueDateColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDue(task.dueDate!, task.dueHasTime),
                              style: TextStyle(
                                color: dueDateColor,
                                fontSize: 12,
                                fontWeight: isLate
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                          if (task.dueDate != null &&
                              task.durationMinutes != 30)
                            const SizedBox(width: 12),
                          if (task.durationMinutes != 30) ...[
                            Icon(Icons.hourglass_bottom_rounded,
                                size: 12,
                                color: palette.text.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(task.durationMinutes),
                              style: TextStyle(
                                  color: palette.text.withValues(alpha: 0.5),
                                  fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    )
                  : null,
              trailing: IconButton(
                icon: Icon(
                  task.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: task.isPinned
                      ? palette.primary
                      : palette.text.withValues(alpha: 0.3),
                  size: 20,
                ),
                onPressed: () => repo.togglePin(task.id),
              ),
              onTap: () => ref.read(quickAddProvider.notifier).expand(task),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDue(DateTime due, bool hasTime) {
    final localDue = due.toLocal();
    final date =
        '${localDue.year}-${localDue.month.toString().padLeft(2, '0')}-'
        '${localDue.day.toString().padLeft(2, '0')}';
    if (!hasTime) return date;
    return '$date ${localDue.hour.toString().padLeft(2, '0')}:'
        '${localDue.minute.toString().padLeft(2, '0')}';
  }
}
