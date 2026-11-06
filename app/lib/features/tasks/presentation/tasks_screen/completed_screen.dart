part of '../tasks_screen.dart';

class _CompletedScreen extends ConsumerWidget {
  const _CompletedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listId = ref.watch(selectedTaskListProvider);
    final completedAsync = ref.watch(completedProvider(listId));
    return Scaffold(
      appBar: AppBar(title: const Text('Completed')),
      body: completedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 48),
                  SizedBox(height: 8),
                  Text('Nothing completed yet'),
                ],
              ),
            );
          }
          final listsById = ref.watch(taskListsByIdProvider);
          return RepaintBoundary(
            child: ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, i) {
                final t = tasks[i];
                final list = t.listId == null ? null : listsById[t.listId];
                final isMs = isMicrosoftTask(
                  taskMicrosoftAccount: t.microsoftAccount,
                  listMicrosoftAccount: list?.microsoftAccount,
                );
                final source = sourceLabel(
                  name: list?.name,
                  account: accountForSource(
                    googleAccount: t.googleAccount,
                    microsoftAccount: t.microsoftAccount,
                  ),
                  fallbackAccount: accountForSource(
                    googleAccount: list?.googleAccount,
                    microsoftAccount: list?.microsoftAccount,
                  ),
                );
                return ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(t.title),
                  subtitle: (source == null && t.dueDate == null)
                      ? null
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (source != null)
                              InkWell(
                                onTap: isMs
                                    ? null
                                    : () => pickAndMoveTask(
                                        context,
                                        ref,
                                        taskId: t.id,
                                        currentListId: t.listId,
                                      ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(child: Text(source)),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.swap_horiz, size: 14),
                                  ],
                                ),
                              ),
                            if (t.dueDate != null)
                              Text(
                                DeviceDateFormat.dateIso(context, t.dueDate!),
                              ),
                          ],
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.undo),
                    tooltip: 'Reopen',
                    onPressed: isMs
                        ? null
                        : () => ref
                              .read(taskRepositoryProvider)
                              .uncompleteTask(t.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
