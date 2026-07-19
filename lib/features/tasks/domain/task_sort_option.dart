enum TaskSortOption {
  priority,
  dueDate,
  createdAt,
  custom;

  String get label {
    switch (this) {
      case TaskSortOption.priority: return 'Priority';
      case TaskSortOption.dueDate: return 'Due Date';
      case TaskSortOption.createdAt: return 'Creation Date';
      case TaskSortOption.custom: return 'Custom Order';
    }
  }
}
