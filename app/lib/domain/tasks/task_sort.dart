// User-selectable task and task-list sort modes. Persisted by name in
// SharedPreferences; unknown values fall back to the previous defaults.
library;

enum TaskSort { custom, name, created, due }

extension TaskSortLabel on TaskSort {
  String get label => switch (this) {
    TaskSort.custom => 'Custom order',
    TaskSort.name => 'Name',
    TaskSort.created => 'Created',
    TaskSort.due => 'Due date',
  };

  static TaskSort parse(Object? value) {
    if (value is! String) return TaskSort.due;
    for (final sort in TaskSort.values) {
      if (sort.name == value) return sort;
    }
    return TaskSort.due;
  }
}

enum TaskListSort { custom, name, created }

extension TaskListSortLabel on TaskListSort {
  String get label => switch (this) {
    TaskListSort.custom => 'Custom order',
    TaskListSort.name => 'Name',
    TaskListSort.created => 'Created',
  };

  static TaskListSort parse(Object? value) {
    if (value is! String) return TaskListSort.custom;
    for (final sort in TaskListSort.values) {
      if (sort.name == value) return sort;
    }
    return TaskListSort.custom;
  }
}
