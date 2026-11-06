part of '../tasks_screen.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listId = ref.watch(selectedTaskListProvider);
    final selectedSmartId = ref.watch(selectedSmartListProvider);
    final smartLists =
        ref.watch(smartListsProvider).value ?? const <SmartList>[];
    final smart = selectedSmartId == null
        ? null
        : smartLists.where((s) => s.id == selectedSmartId).firstOrNull;
    final tasksAsync = smart == null
        ? ref.watch(openTasksProvider(listId))
        : ref.watch(smartListTasksProvider(smart));
    final listsAsync = ref.watch(taskListsProvider);
    final taskSort = ref.watch(taskSortProvider).value ?? TaskSort.due;
    final listSort =
        ref.watch(taskListSortProvider).value ?? TaskListSort.custom;
    return Scaffold(
      appBar: AppBar(
        title: const SyncTitle(text: 'Tasks'),
        actions: [
          if (smart == null)
            PopupMenuButton<TaskSort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Sort tasks',
              initialValue: taskSort,
              onSelected: (mode) =>
                  ref.read(taskSortProvider.notifier).select(mode),
              itemBuilder: (_) => [
                for (final mode in TaskSort.values)
                  PopupMenuItem(value: mode, child: Text(mode.label)),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Completed',
            onPressed: () => _showCompleted(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
            ),
          ),
          PopupMenuButton<_TasksAction>(
            tooltip: 'Task organization',
            onSelected: (action) {
              switch (action) {
                case _TasksAction.manageLists:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TaskListsScreen(),
                    ),
                  );
                case _TasksAction.manageSmartLists:
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SmartListsScreen(),
                    ),
                  );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _TasksAction.manageLists,
                child: Text('Manage lists'),
              ),
              PopupMenuItem(
                value: _TasksAction.manageSmartLists,
                child: Text('Manage smart lists'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          listsAsync.maybeWhen(
            data: (lists) {
              final sortedLists = [...lists]
                ..sort((a, b) => compareTaskLists(a, b, listSort));
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: smart == null && listId == null,
                      onSelected: (_) => _select(ref, null),
                    ),
                    const SizedBox(width: 8),
                    for (final l in sortedLists) ...[
                      GestureDetector(
                        onLongPress: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TaskListsScreen(),
                          ),
                        ),
                        child: Tooltip(
                          message:
                              taskListAccountLabel(l) ??
                              (l.remoteId == null
                                  ? localSourceLabel
                                  : 'Google'),
                          child: ChoiceChip(
                            avatar: TaskListColorDot(list: l, size: 10),
                            label: Text(l.name),
                            selected: smart == null && listId == l.id,
                            onSelected: (_) => _select(ref, l.id),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    for (final s in smartLists) ...[
                      _SmartListChip(
                        smartList: s,
                        selected: smart?.id == s.id,
                        onSelected: () => _selectSmart(ref, s.id),
                        onLongPress: () => _smartActions(context, ref, s),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ActionChip(
                      label: const Text('+ List'),
                      onPressed: () => showCreateTaskListDialog(context, ref),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('+ Smart list'),
                      onPressed: () => showSmartListEditor(context),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                message: 'Could not load tasks.',
                onRetry: () {
                  if (smart == null) {
                    ref.invalidate(openTasksProvider(listId));
                  } else {
                    ref.invalidate(smartListTasksProvider(smart));
                  }
                },
              ),
              data: (tasks) {
                if (tasks.isEmpty) {
                  if (smart != null) {
                    return EmptyState(
                      icon: Icons.filter_alt_off,
                      title: 'No tasks match',
                      subtitle: 'Nothing matches "${smart.name}" right now.',
                      actionLabel: 'Edit smart list',
                      onAction: () =>
                          showSmartListEditor(context, smartList: smart),
                    );
                  }
                  return EmptyState(
                    icon: Icons.checklist_outlined,
                    title: 'No tasks here',
                    actionLabel: 'Add a task',
                    onAction: () => showQuickAdd(context),
                  );
                }
                // Smart lists keep the sort saved in their filter JSON.
                final sortedTasks = smart == null
                    ? ([...tasks]..sort((a, b) => compareTasks(a, b, taskSort)))
                    : tasks;
                if (smart == null && taskSort == TaskSort.custom) {
                  return _CustomTaskList(tasks: sortedTasks);
                }
                final today = _today();
                final overdue = sortedTasks
                    .where(
                      (t) =>
                          t.dueDate != null && t.dueDate!.compareTo(today) < 0,
                    )
                    .toList();
                final overdueIds = overdue.map((t) => t.id).toSet();
                final rest = sortedTasks
                    .where((t) => !overdueIds.contains(t.id))
                    .toList();
                final items = <Widget>[];
                if (overdue.isNotEmpty) {
                  items.add(
                    ListTile(
                      title: Text('Overdue (${overdue.length})'),
                      trailing: TextButton(
                        onPressed: () => _rescheduleAll(context, ref, overdue),
                        child: const Text('Reschedule to today'),
                      ),
                    ),
                  );
                  items.addAll(
                    overdue.map((t) => _TaskTile(task: t, overdue: true)),
                  );
                }
                items.addAll(rest.map((t) => _TaskTile(task: t)));
                return RepaintBoundary(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) => items[i],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'tasksFab',
        onPressed: () => showQuickAdd(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
