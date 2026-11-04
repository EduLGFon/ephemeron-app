// Riverpod providers for tasks. UI reads only from Drift streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/tasks/eisenhower.dart';
import '../../../domain/tasks/smart_filter.dart';
import '../../../domain/tasks/task_sort.dart';
import '../../settings/application/settings_providers.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
});

final taskListsProvider = StreamProvider<List<TaskList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchLists();
});

/// Lists keyed by id for cheap source labels in tiles and detail sheets.
final taskListsByIdProvider = Provider<Map<String, TaskList>>((ref) {
  final lists = ref.watch(taskListsProvider).value ?? const <TaskList>[];
  return {for (final list in lists) list.id: list};
});

final tagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTags();
});

final smartListsProvider = StreamProvider<List<SmartList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchSmartLists();
});

/// Reactive results for one saved view. Chips and the manage screen may watch
/// several of these; keep each one a single indexed Drift query.
final smartListTasksProvider = StreamProvider.family<List<Task>, SmartList>((
  ref,
  smartList,
) {
  final filter = SmartFilter.fromJson(smartList.filterJson);
  return ref.watch(taskRepositoryProvider).watchSmartList(filter.toMap());
});

final openTasksProvider = StreamProvider.family<List<Task>, String?>((
  ref,
  listId,
) {
  return ref.watch(taskRepositoryProvider).watchOpen(listId: listId);
});

final trashProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTrash();
});

final completedProvider = StreamProvider.family<List<Task>, String?>((
  ref,
  listId,
) {
  return ref.watch(taskRepositoryProvider).watchCompleted(listId: listId);
});

final subtasksProvider = StreamProvider.family<List<Task>, String>((
  ref,
  parentId,
) {
  return ref.watch(taskRepositoryProvider).watchSubtasks(parentId);
});

/// Null means all lists.
final selectedTaskListProvider = NotifierProvider<SelectedTaskList, String?>(
  SelectedTaskList.new,
);

class SelectedTaskList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// Saved smart list currently filtering the Tasks screen. Null means normal
/// list mode. Selecting a normal list clears this in the UI.
final selectedSmartListProvider = NotifierProvider<SelectedSmartList, String?>(
  SelectedSmartList.new,
);

class SelectedSmartList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

class OccurrenceDirty extends Notifier<bool> {
  @override
  bool build() => true;
  void markDirty() => state = true;
  void clear() => state = false;
}

final occurrenceDirtyProvider = NotifierProvider<OccurrenceDirty, bool>(
  OccurrenceDirty.new,
);

/// Task sort mode, persisted in shared preferences. Default preserves the
/// pre-existing due-date order.
final taskSortProvider = AsyncNotifierProvider<TaskSortNotifier, TaskSort>(
  TaskSortNotifier.new,
);

class TaskSortNotifier extends AsyncNotifier<TaskSort> {
  @override
  Future<TaskSort> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    return TaskSortLabel.parse(repo.taskSort);
  }

  Future<void> select(TaskSort sort) async {
    state = AsyncData(sort);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setTaskSort(sort.name);
    } catch (_) {
      // Best-effort persistence: keep the chosen mode for this session.
    }
  }
}

/// Task-list sort mode, persisted in shared preferences.
final taskListSortProvider =
    AsyncNotifierProvider<TaskListSortNotifier, TaskListSort>(
      TaskListSortNotifier.new,
    );

class TaskListSortNotifier extends AsyncNotifier<TaskListSort> {
  @override
  Future<TaskListSort> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    return TaskListSortLabel.parse(repo.taskListSort);
  }

  Future<void> select(TaskListSort sort) async {
    state = AsyncData(sort);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setTaskListSort(sort.name);
    } catch (_) {
      // Best-effort persistence: keep the chosen mode for this session.
    }
  }
}

/// Matrix grouping mode, persisted in shared preferences.
final matrixModeProvider =
    AsyncNotifierProvider<MatrixModeNotifier, MatrixMode>(
      MatrixModeNotifier.new,
    );

class MatrixModeNotifier extends AsyncNotifier<MatrixMode> {
  @override
  Future<MatrixMode> build() async {
    final repo = await ref.watch(settingsRepositoryProvider.future);
    return matrixModeFromName(repo.matrixMode);
  }

  Future<void> select(MatrixMode mode) async {
    state = AsyncData(mode);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setMatrixMode(mode.name);
    } catch (_) {
      // Best-effort persistence: keep the chosen mode for this session.
    }
  }
}
