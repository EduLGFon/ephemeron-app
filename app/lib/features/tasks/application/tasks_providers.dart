// Riverpod providers for tasks. UI reads only from Drift streams.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_provider.dart';
import '../../../data/drift/app_database.dart';
import '../../../data/repositories/task_repository.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(appDatabaseProvider));
});

final taskListsProvider = StreamProvider<List<TaskList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchLists();
});

final tagsProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTags();
});

final smartListsProvider = StreamProvider<List<SmartList>>((ref) {
  return ref.watch(taskRepositoryProvider).watchSmartLists();
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
