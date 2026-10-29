import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/task_providers.dart';
import '../domain/task_sort_option.dart';
import '../../../presentation/widgets/confirmation_dialog.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

import 'task_list_selector.dart';
import 'task_tile.dart';
import 'completed_tasks_section.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(listsProvider);
    final customSmartListsAsync = ref.watch(customSmartListsProvider);
    final tagsAsync = ref.watch(allTagsProvider);
    final palette = ref.watch(themeEngineProvider);
    final sortOption = ref.watch(taskSortOptionProvider);
    final selectedListId = ref.watch(selectedListIdProvider);

    final lists = listsAsync.value ?? [];
    final customSmartLists = customSmartListsAsync.value ?? [];
    final tags = tagsAsync.value ?? [];

    final TaskList? defaultInbox = lists.isEmpty
        ? null
        : lists.firstWhere((l) => l.isInbox, orElse: () => lists.first);
    final defaultInboxId = defaultInbox?.id ?? '';
    final currentId = selectedListId ?? defaultInboxId;
    final currentListName =
        _getCurrentListName(lists, customSmartLists, currentId);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: TaskListSelector(
          palette: palette,
          currentId: currentId,
          currentListName: currentListName,
          lists: lists,
          customSmartLists: customSmartLists,
          tags: tags,
        ),
        actions: [
          if (currentId.startsWith('custom_smart:'))
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined,
                  color: Colors.redAccent.withValues(alpha: 0.8)),
              tooltip: 'Delete smart list',
              onPressed: () async {
                final confirm = await showConfirmationDialog(
                  context: context,
                  ref: ref,
                  title: 'Delete Smart List?',
                  content:
                      'Are you sure you want to delete this custom smart list?',
                  confirmLabel: 'Delete',
                  isDestructive: true,
                );
                if (confirm) {
                  final id = currentId.substring(13);
                  await ref
                      .read(taskRepositoryProvider)
                      .deleteCustomSmartList(id);
                  ref.read(selectedListIdProvider.notifier).state = null;
                }
              },
            ),
          const SizedBox(width: 8),
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: palette.surface.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: TextStyle(color: palette.text),
              ),
            ),
            child: PopupMenuButton<TaskSortOption>(
              icon: Icon(Icons.menu, color: palette.text),
              tooltip: 'Sorting options',
              onSelected: (option) {
                ref.read(taskSortOptionProvider.notifier).setSortOption(option);
              },
              itemBuilder: (context) => [
                for (final opt in TaskSortOption.values)
                  PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          opt == sortOption
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: opt == sortOption
                              ? palette.primary
                              : palette.text.withValues(alpha: 0.4),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(opt.label,
                            style:
                                TextStyle(color: palette.text, fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: listsAsync.when(
        data: (lists) {
          final currentId = selectedListId ??
              lists.firstWhere((l) => l.isInbox, orElse: () => lists.first).id;
          return _TaskListView(listId: currentId, palette: palette);
        },
        loading: () => const Center(child: AppLoadingIndicator()),
        error: (error, _) => Center(
          child: Text('Could not load lists: $error',
              style: TextStyle(color: palette.text)),
        ),
      ),
    );
  }

  String _getCurrentListName(List<TaskList> lists,
      List<CustomSmartList> customSmartLists, String currentId) {
    if (currentId.startsWith('smart:')) {
      final typeStr = currentId.substring(6);
      return switch (typeStr) {
        'today' => 'Today',
        'tomorrow' => 'Tomorrow',
        'next7Days' => 'Next 7 Days',
        'completed' => 'Completed',
        'trash' => 'Trash',
        'wontDo' => "Won't Do",
        _ => typeStr,
      };
    }
    if (currentId.startsWith('custom_smart:')) {
      final id = currentId.substring(13);
      final CustomSmartList? customList = customSmartLists.isEmpty
          ? null
          : customSmartLists.firstWhere(
              (s) => s.id == id,
              orElse: () => null as dynamic,
            );
      return customList?.name ?? 'Smart List';
    }
    final TaskList? list = lists.isEmpty
        ? null
        : lists.firstWhere(
            (l) => l.id == currentId,
            orElse: () => null as dynamic,
          );
    return list?.name ?? 'Tasks';
  }
}

class _TaskListView extends ConsumerWidget {
  const _TaskListView({required this.listId, required this.palette});

  final String listId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingTasksInListProvider(listId));
    final completedAsync = ref.watch(completedTasksInListProvider(listId));

    return pendingAsync.when(
      data: (pendingTasks) {
        return completedAsync.when(
          data: (completedTasks) {
            final showDirectly = listId == 'smart:completed' ||
                listId == 'smart:trash' ||
                listId == 'smart:wontDo';

            if (showDirectly) {
              final tasksToShow =
                  completedTasks.isNotEmpty ? completedTasks : pendingTasks;
              if (tasksToShow.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: palette.text.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        'No tasks found',
                        style: TextStyle(
                            color: palette.text.withValues(alpha: 0.5),
                            fontSize: 16),
                      ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: tasksToShow.length,
                itemBuilder: (context, index) {
                  final task = tasksToShow[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: RepaintBoundary(
                        child: TaskTile(task: task, palette: palette)),
                  );
                },
              );
            }

            if (pendingTasks.isEmpty && completedTasks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 64, color: palette.text.withValues(alpha: 0.1)),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks yet',
                      style: TextStyle(
                          color: palette.text.withValues(alpha: 0.5),
                          fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                if (pendingTasks.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverReorderableList(
                      itemCount: pendingTasks.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIdx, newIdx) async {
                        if (oldIdx < newIdx) {
                          newIdx -= 1;
                        }
                        final mutableList = List<Task>.from(pendingTasks);
                        final item = mutableList.removeAt(oldIdx);
                        mutableList.insert(newIdx, item);

                        ref
                            .read(taskSortOptionProvider.notifier)
                            .setSortOption(TaskSortOption.custom);

                        final ids = mutableList.map((t) => t.id).toList();
                        await ref
                            .read(taskRepositoryProvider)
                            .updateTaskSortOrders(ids);
                      },
                      itemBuilder: (context, index) {
                        final task = pendingTasks[index];
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(task.id),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: RepaintBoundary(
                                child: TaskTile(task: task, palette: palette)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (completedTasks.isNotEmpty)
                  CompletedTasksSection(
                    completedTasks: completedTasks,
                    palette: palette,
                  ),
              ],
            );
          },
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, _) => Center(
              child: Text('Could not load completed tasks: $error',
                  style: TextStyle(color: palette.text))),
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (error, _) => Center(
          child: Text('Could not load tasks: $error',
              style: TextStyle(color: palette.text))),
    );
  }
}
