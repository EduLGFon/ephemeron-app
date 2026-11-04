// Pure comparators shared by the Tasks screen and the list manager.
import '../../../data/drift/app_database.dart';
import '../../../domain/tasks/task_sort.dart';

int compareTasks(Task a, Task b, TaskSort sort) {
  // Pinned tasks stay on top in every mode except explicit custom order.
  if (sort != TaskSort.custom) {
    final pinned = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
    if (pinned != 0) return pinned;
  }
  var cmp = switch (sort) {
    TaskSort.custom => a.sortOrder.compareTo(b.sortOrder),
    TaskSort.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    TaskSort.created => b.createdAt.compareTo(a.createdAt),
    TaskSort.due => _compareDue(a.dueDate, b.dueDate),
  };
  if (cmp == 0) cmp = a.sortOrder.compareTo(b.sortOrder);
  if (cmp == 0) cmp = a.id.compareTo(b.id);
  return cmp;
}

int compareTaskLists(TaskList a, TaskList b, TaskListSort sort) {
  var cmp = switch (sort) {
    TaskListSort.custom => a.sortOrder.compareTo(b.sortOrder),
    TaskListSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    TaskListSort.created => b.createdAt.compareTo(a.createdAt),
  };
  if (cmp == 0) cmp = a.id.compareTo(b.id);
  return cmp;
}

/// Due dates sort ascending with undated tasks last.
int _compareDue(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
