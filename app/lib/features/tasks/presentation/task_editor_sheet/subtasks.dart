part of '../task_editor_sheet.dart';

class _SubtaskSection extends ConsumerWidget {
  const _SubtaskSection({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsById = ref.watch(taskListsByIdProvider);
    final parentMs = isMicrosoftTask(
      taskMicrosoftAccount: task.microsoftAccount,
      listMicrosoftAccount:
          (task.listId == null ? null : listsById[task.listId])
              ?.microsoftAccount,
    );
    final subsAsync = ref.watch(subtasksProvider(task.id));
    return subsAsync.maybeWhen(
      data: (subs) {
        final done = subs.where((s) => s.completedAt != null).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Subtasks $done/${subs.length}'),
            for (final s in subs)
              Builder(
                builder: (context) {
                  final subList = s.listId == null ? null : listsById[s.listId];
                  final subMs = isMicrosoftTask(
                    taskMicrosoftAccount: s.microsoftAccount,
                    listMicrosoftAccount: subList?.microsoftAccount,
                  );
                  final readOnly = parentMs || subMs;
                  return CheckboxListTile(
                    value: s.completedAt != null,
                    onChanged: readOnly
                        ? null
                        : (_) {
                            final repo = ref.read(taskRepositoryProvider);
                            if (s.completedAt != null) {
                              repo.uncompleteTask(s.id);
                            } else {
                              repo.completeTask(s.id);
                            }
                          },
                    title: Text(s.title),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            if (!parentMs)
              TextButton.icon(
                onPressed: () => showTaskEditor(context, parentId: task.id),
                icon: const Icon(Icons.add),
                label: const Text('Add subtask'),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
