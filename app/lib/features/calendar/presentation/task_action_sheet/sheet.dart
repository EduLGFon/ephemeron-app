part of '../task_action_sheet.dart';

class TaskActionSheet extends ConsumerWidget {
  const TaskActionSheet({
    super.key,
    required this.taskId,
    required this.occurrenceDate,
  });

  final String taskId;
  final String occurrenceDate;

  bool _isFutureOccurrence(Task task) {
    String? effective;
    if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
      effective = task.plannedStart!.length >= 10
          ? task.plannedStart!.substring(0, 10)
          : task.plannedStart;
    } else if (task.plannedDate != null) {
      effective = task.plannedDate;
    } else {
      effective = task.dueDate;
    }
    if (effective == null) return false;
    return occurrenceDate.compareTo(effective) > 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final repo = ref.watch(taskRepositoryProvider);
    final lists = ref
        .watch(taskListsProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <TaskList>[]);

    final stream = (db.select(
      db.tasks,
    )..where((t) => t.id.equals(taskId))).watchSingleOrNull();

    return StreamBuilder<Task?>(
      stream: stream,
      builder: (context, snap) {
        final task = snap.data;
        if (task == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final isFuture = _isFutureOccurrence(task);
        final isRecurring = task.rrule != null && task.rrule!.isNotEmpty;
        final currentKey = repo.currentTaskOccurrenceKey(task);
        final isProjectedOccurrence =
            isRecurring && occurrenceDate != currentKey;
        TaskList? list;
        for (final l in lists) {
          if (l.id == task.listId) {
            list = l;
            break;
          }
        }
        final sourceLabel = list?.name ?? 'Tasks';
        final isMs = isMicrosoftTask(
          taskMicrosoftAccount: task.microsoftAccount,
          listMicrosoftAccount: list?.microsoftAccount,
        );

        DateTime? plannedDt;
        String? timeStr;
        if (task.plannedStart != null && task.plannedStart!.isNotEmpty) {
          plannedDt = DateTime.tryParse(task.plannedStart!);
          if (plannedDt != null) {
            timeStr = DeviceDateFormat.time(context, plannedDt);
            if (task.plannedEnd != null && task.plannedEnd!.isNotEmpty) {
              final endDt = DateTime.tryParse(task.plannedEnd!);
              if (endDt != null) {
                timeStr = '$timeStr - ${DeviceDateFormat.time(context, endDt)}';
              }
            }
          }
        } else if (task.plannedDate != null) {
          final p = task.plannedDate!.split('-');
          plannedDt = DateTime(
            int.parse(p[0]),
            int.parse(p[1]),
            int.parse(p[2]),
          );
          if (task.dueTime != null) {
            plannedDt = DateTime(
              plannedDt.year,
              plannedDt.month,
              plannedDt.day,
              task.dueTime! ~/ 60,
              task.dueTime! % 60,
            );
            timeStr = DeviceDateFormat.time(context, plannedDt);
          }
        } else if (task.dueDate != null) {
          final p = task.dueDate!.split('-');
          plannedDt = DateTime(
            int.parse(p[0]),
            int.parse(p[1]),
            int.parse(p[2]),
          );
          if (task.dueTime != null) {
            plannedDt = DateTime(
              plannedDt.year,
              plannedDt.month,
              plannedDt.day,
              task.dueTime! ~/ 60,
              task.dueTime! % 60,
            );
            timeStr = DeviceDateFormat.time(context, plannedDt);
          }
        }
        final dateStr = plannedDt == null
            ? occurrenceDate
            : DeviceDateFormat.date(context, plannedDt);
        final when = timeStr == null ? dateStr : '$dateStr - $timeStr';

        final done = task.completedAt != null;
        final wontDo = task.wontDo;

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$sourceLabel  •  $when',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isFuture) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Future occurrence',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              if (!isMs) ...[
                if (isProjectedOccurrence) ...[
                  ListTile(
                    leading: const Icon(Icons.check_rounded),
                    title: const Text('Mark as concluded'),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await repo.completeTaskOccurrence(task, occurrenceDate);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: const Text("Won't do"),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await repo.markWontDoTaskOccurrence(task, occurrenceDate);
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: Icon(
                      done ? Icons.undo_rounded : Icons.check_rounded,
                    ),
                    title: Text(
                      done ? 'Mark as not concluded' : 'Mark as concluded',
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      if (done) {
                        await repo.uncompleteTask(taskId);
                      } else {
                        await repo.completeTask(taskId);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: const Text("Won't do"),
                    enabled: !wontDo,
                    onTap: wontDo
                        ? null
                        : () async {
                            Navigator.of(context).pop();
                            await repo.markWontDo(taskId);
                          },
                  ),
                ],
              ],
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open tasks'),
                onTap: () {
                  final router = GoRouter.maybeOf(context);
                  Navigator.of(context).pop();
                  router?.go('/tab1');
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Subtasks',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              StreamBuilder<List<Task>>(
                stream: repo.watchSubtasks(taskId),
                builder: (context, subSnap) {
                  final subs = subSnap.data ?? const <Task>[];
                  if (subs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text('No subtasks'),
                    );
                  }
                  return Column(
                    children: [
                      for (final s in subs)
                        Builder(
                          builder: (context) {
                            final subMs = isMicrosoftTask(
                              taskMicrosoftAccount: s.microsoftAccount,
                              listMicrosoftAccount: list?.microsoftAccount,
                            );
                            final readOnly = isMs || subMs;
                            return ListTile(
                              leading: IconButton(
                                icon: Icon(
                                  s.completedAt != null
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                ),
                                onPressed: readOnly
                                    ? null
                                    : () async {
                                        if (s.completedAt != null) {
                                          await repo.uncompleteTask(s.id);
                                        } else {
                                          await repo.completeTask(s.id);
                                        }
                                      },
                              ),
                              title: Text(s.title),
                              onTap: readOnly
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      showTaskEditor(context, task: s);
                                    },
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
