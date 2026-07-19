import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/local/database.dart';
import '../../../data/local/database_provider.dart';
import '../../alarms/application/alarm_scheduler_provider.dart';
import '../../auth/google/google_auth_provider.dart';
import '../domain/smart_list_type.dart';
import '../domain/task_sort_option.dart';
import '../data/google_tasks_mirror.dart';
import '../data/task_repository.dart';

/// Null whenever no Google account is connected — TaskRepository treats
/// that exactly like "the mirror push failed," so nothing else needs to
/// branch on connection state separately.
final googleTasksMirrorProvider = Provider<GoogleTasksMirror?>((ref) {
  final account = ref.watch(googleAccountProvider).value;
  if (account == null) return null;
  return GoogleTasksMirror(ref.watch(googleAuthRepositoryProvider));
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(alarmSchedulerProvider),
    ref.watch(googleTasksMirrorProvider),
  );
});

final listsProvider = StreamProvider<List<TaskList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchLists();
});

final tasksInListProvider = StreamProvider.family<List<Task>, String>((
  ref,
  listId,
) {
  return ref.watch(taskRepositoryProvider).watchTasksInList(listId);
});

final customSmartListsProvider = StreamProvider<List<CustomSmartList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchCustomSmartLists();
});

final customSmartListByIdProvider = StreamProvider.family<CustomSmartList?, String>((ref, id) {
  return ref.watch(taskRepositoryProvider).watchCustomSmartListById(id);
});

final tasksForListProvider = StreamProvider.family<List<Task>, String>((ref, listId) {
  final repo = ref.watch(taskRepositoryProvider);
  if (listId.startsWith('smart:')) {
    final typeStr = listId.substring(6);
    final type = SmartListType.values.firstWhere((e) => e.name == typeStr);
    return repo.watchSmartList(type);
  } else if (listId.startsWith('custom_smart:')) {
    final id = listId.substring(13);
    final smartListAsync = ref.watch(customSmartListByIdProvider(id));
    return smartListAsync.when(
      data: (smartList) {
        if (smartList == null) return Stream.value(<Task>[]);
        return repo.watchTasksForCustomSmartList(smartList);
      },
      loading: () => const Stream<List<Task>>.empty(),
      error: (err, stack) => Stream<List<Task>>.error(err, stack),
    );
  } else {
    return repo.watchTasksInList(listId);
  }
});

final allPendingTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllPendingTasks();
});

final allActiveTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllActiveTasks();
});

final subtasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  parentTaskId,
) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(parentTaskId);
});

final smartListProvider = StreamProvider.family<List<Task>, SmartListType>((
  ref,
  type,
) {
  return ref.watch(taskRepositoryProvider).watchSmartList(type);
});

final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllTags();
});

final taskTagsProvider = StreamProvider.family<List<Tag>, String>((
  ref,
  taskId,
) {
  return ref.watch(taskRepositoryProvider).watchTagsForTask(taskId);
});



class TaskSortOptionNotifier extends Notifier<TaskSortOption> {
  @override
  TaskSortOption build() => TaskSortOption.priority;

  void setSortOption(TaskSortOption option) {
    state = option;
  }
}

final taskSortOptionProvider = NotifierProvider<TaskSortOptionNotifier, TaskSortOption>(() {
  return TaskSortOptionNotifier();
});

List<Task> _applyInMemorySort(List<Task> tasks, TaskSortOption sortOption, {required bool isCompleted}) {
  final filtered = tasks.where((t) => t.isCompleted == isCompleted).toList();
  
  if (isCompleted) {
    filtered.sort((a, b) {
      final ca = a.completedAt ?? a.updatedAt;
      final cb = b.completedAt ?? b.updatedAt;
      return cb.compareTo(ca);
    });
    return filtered;
  }

  switch (sortOption) {
    case TaskSortOption.priority:
      filtered.sort((a, b) {
        final pComp = b.priority.compareTo(a.priority);
        if (pComp != 0) return pComp;
        if (a.dueDate == null && b.dueDate == null) return a.createdAt.compareTo(b.createdAt);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
    case TaskSortOption.dueDate:
      filtered.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return b.priority.compareTo(a.priority);
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        final dComp = a.dueDate!.compareTo(b.dueDate!);
        if (dComp != 0) return dComp;
        return b.priority.compareTo(a.priority);
      });
    case TaskSortOption.createdAt:
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case TaskSortOption.custom:
      filtered.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
  return filtered;
}

final pendingTasksInListProvider = StreamProvider.family<List<Task>, String>((ref, listId) {
  final repo = ref.watch(taskRepositoryProvider);
  final sortOption = ref.watch(taskSortOptionProvider);

  if (listId.startsWith('smart:')) {
    final typeStr = listId.substring(6);
    final type = SmartListType.values.firstWhere((e) => e.name == typeStr);
    return repo.watchSmartList(type).map((tasks) => _applyInMemorySort(tasks, sortOption, isCompleted: false));
  } else if (listId.startsWith('custom_smart:')) {
    final id = listId.substring(13);
    final smartListAsync = ref.watch(customSmartListByIdProvider(id));
    return smartListAsync.when(
      data: (smartList) {
        if (smartList == null) return Stream.value(<Task>[]);
        return repo.watchTasksForCustomSmartList(smartList).map((tasks) => _applyInMemorySort(tasks, sortOption, isCompleted: false));
      },
      loading: () => const Stream<List<Task>>.empty(),
      error: (err, stack) => Stream<List<Task>>.error(err, stack),
    );
  } else {
    return repo.watchTasksInList(listId, isCompleted: false, sortOption: sortOption);
  }
});

final completedTasksInListProvider = StreamProvider.family<List<Task>, String>((ref, listId) {
  final repo = ref.watch(taskRepositoryProvider);
  
  if (listId.startsWith('smart:')) {
    final typeStr = listId.substring(6);
    final type = SmartListType.values.firstWhere((e) => e.name == typeStr);
    return repo.watchSmartList(type).map((tasks) => _applyInMemorySort(tasks, TaskSortOption.priority, isCompleted: true));
  } else if (listId.startsWith('custom_smart:')) {
    final id = listId.substring(13);
    final smartListAsync = ref.watch(customSmartListByIdProvider(id));
    return smartListAsync.when(
      data: (smartList) {
        if (smartList == null) return Stream.value(<Task>[]);
        return repo.watchTasksForCustomSmartList(smartList).map((tasks) => _applyInMemorySort(tasks, TaskSortOption.priority, isCompleted: true));
      },
      loading: () => const Stream<List<Task>>.empty(),
      error: (err, stack) => Stream<List<Task>>.error(err, stack),
    );
  } else {
    return repo.watchTasksInList(listId, isCompleted: true);
  }
});

final selectedListIdProvider = StateProvider<String?>((ref) => null);

final calendarTasksProvider = StreamProvider<List<TaskCalendarEntry>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTasksForCalendar();
});

