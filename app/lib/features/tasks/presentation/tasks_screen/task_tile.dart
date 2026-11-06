part of '../tasks_screen.dart';

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, this.overdue = false});

  final Task task;
  final bool overdue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = task.listId == null
        ? null
        : ref.watch(taskListsByIdProvider)[task.listId];
    final source = sourceLabel(
      name: list?.name,
      account: accountForSource(
        googleAccount: task.googleAccount,
        microsoftAccount: task.microsoftAccount,
      ),
      fallbackAccount: accountForSource(
        googleAccount: list?.googleAccount,
        microsoftAccount: list?.microsoftAccount,
      ),
    );
    final isMs = isMicrosoftTask(
      taskMicrosoftAccount: task.microsoftAccount,
      listMicrosoftAccount: list?.microsoftAccount,
    );
    return Dismissible(
      direction: isMs ? DismissDirection.none : DismissDirection.horizontal,
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
        if (isMs) return false;
        final repo = ref.read(taskRepositoryProvider);
        if (dir == DismissDirection.startToEnd) {
          await repo.completeTask(task.id);
          if (context.mounted) {
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
          return false;
        }
        return true;
      },
      onDismissed: (_) async {
        final pending = ref.read(pendingOperationsProvider);
        final opId = await pending.scheduleTaskDelete(task.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${task.title}"'),
              duration: const Duration(seconds: 6),
              persist: false,
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => pending.cancel(opId),
              ),
            ),
          );
        }
      },
      child: ListTile(
        leading: Checkbox(
          value: false,
          onChanged: isMs
              ? null
              : (_) async {
                  final repo = ref.read(taskRepositoryProvider);
                  await repo.completeTask(task.id);
                  if (context.mounted) {
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
                },
        ),
        title: Text(
          task.title,
          style: overdue ? const TextStyle(color: Colors.red) : null,
        ),
        subtitle: _subtitle(context, ref, source),
        trailing: _MoveButtons(task: task),
        onTap: isMs ? null : () => showTaskEditor(context, task: task),
      ),
    );
  }

  String _formatDate(BuildContext context, String value) {
    try {
      return DeviceDateFormat.yMMMd(context).format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  String _formatDateTime(BuildContext context, String value) {
    try {
      final dt = DateTime.parse(value);
      return '${DeviceDateFormat.yMMMd(context).format(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  Widget? _subtitle(BuildContext context, WidgetRef ref, String? source) {
    final parts = <String>[];
    if (task.plannedStart != null || task.plannedEnd != null) {
      final start = task.plannedStart;
      final end = task.plannedEnd;
      parts.add(
        'Planned ${start == null ? '' : _formatDateTime(context, start)}'
        '${end == null ? '' : ' - ${_formatDateTime(context, end)}'}',
      );
    } else if (task.plannedDate != null) {
      parts.add('Planned ${_formatDate(context, task.plannedDate!)}');
    }
    if (task.dueDate != null) {
      var due = 'Due ${_formatDate(context, task.dueDate!)}';
      if (task.dueTime != null) {
        final h = task.dueTime! ~/ 60;
        final m = task.dueTime! % 60;
        due +=
            ' ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
      parts.add(due);
    }
    if (task.priority > 0) parts.add('P${5 - task.priority}');
    if (task.wontDo) parts.add("Won't do");
    if (source == null && parts.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (source != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => pickAndMoveTask(
                context,
                ref,
                taskId: task.id,
                currentListId: task.listId,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.swap_horiz,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        if (parts.isNotEmpty) Text(parts.join('  ')),
      ],
    );
  }
}
