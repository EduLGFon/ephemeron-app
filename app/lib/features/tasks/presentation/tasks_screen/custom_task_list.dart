part of '../tasks_screen.dart';

/// Custom-order task list. Reordering is optimistic and persisted locally;
/// swipe actions and tap-to-edit stay on the tiles inside.
class _CustomTaskList extends ConsumerStatefulWidget {
  const _CustomTaskList({required this.tasks});

  final List<Task> tasks;

  @override
  ConsumerState<_CustomTaskList> createState() => _CustomTaskListState();
}

class _CustomTaskListState extends ConsumerState<_CustomTaskList> {
  late List<Task> _tasks;

  @override
  void initState() {
    super.initState();
    _tasks = [...widget.tasks];
  }

  @override
  void didUpdateWidget(covariant _CustomTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.tasks, widget.tasks)) {
      _tasks = [...widget.tasks];
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _tasks.removeAt(oldIndex);
      _tasks.insert(newIndex, item);
    });
    _persist();
  }

  Future<void> _persist() async {
    try {
      await ref.read(taskRepositoryProvider).reorderTasks([
        for (final t in _tasks) t.id,
      ]);
    } catch (_) {
      if (mounted) {
        setState(() => _tasks = [...widget.tasks]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: _tasks.length,
        onReorderItem: _onReorder,
        itemBuilder: (context, i) {
          final task = _tasks[i];
          return ReorderableDelayedDragStartListener(
            key: ValueKey('reorder-${task.id}'),
            index: i,
            child: _TaskTile(task: task),
          );
        },
      ),
    );
  }
}
