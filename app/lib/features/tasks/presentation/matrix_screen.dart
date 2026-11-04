// Eisenhower matrix screen: switches between auto classification and stored
// priority grouping, and hosts the board plus task creation entry point.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/tasks/eisenhower.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/tasks_providers.dart';
import 'matrix_board.dart';
import 'quick_add_sheet.dart';

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(openTasksProvider(null));
    final mode = ref
        .watch(matrixModeProvider)
        .maybeWhen(data: (mode) => mode, orElse: () => MatrixMode.auto);
    return Scaffold(
      appBar: AppBar(title: const SyncTitle(text: 'Matrix')),
      floatingActionButton: FloatingActionButton(
        key: const Key('matrix-add-task'),
        heroTag: 'matrixFab',
        tooltip: 'Add task',
        onPressed: () => showQuickAdd(context),
        child: const Icon(Icons.add),
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (tasks) {
          final grouped = _groupTasks(tasks, mode);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _ModeSelector(mode: mode),
              ),
              Expanded(
                child: MatrixBoard(
                  fields: grouped.fields,
                  unclassified: grouped.unclassified,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeSelector extends ConsumerWidget {
  const _ModeSelector({required this.mode});

  final MatrixMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<MatrixMode>(
      segments: const [
        ButtonSegment(value: MatrixMode.auto, label: Text('Auto')),
        ButtonSegment(value: MatrixMode.priority, label: Text('Priority')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      onSelectionChanged: (selected) {
        ref.read(matrixModeProvider.notifier).select(selected.single);
      },
    );
  }
}

({List<MatrixBoardField> fields, List<Task> unclassified}) _groupTasks(
  List<Task> tasks,
  MatrixMode mode,
) {
  if (mode == MatrixMode.priority) {
    final buckets = <int, List<Task>>{4: [], 3: [], 2: [], 1: []};
    final unclassified = <Task>[];
    for (final task in tasks) {
      final bucket = buckets[task.priority];
      if (bucket == null) {
        unclassified.add(task);
      } else {
        bucket.add(task);
      }
    }
    return (
      fields: [
        for (final priority in const [4, 3, 2, 1])
          MatrixBoardField(
            id: matrixPriorityLabel(priority)!.toLowerCase(),
            title: matrixPriorityLabel(priority)!,
            tasks: buckets[priority]!,
          ),
      ],
      unclassified: unclassified,
    );
  }

  final groups = <EisenhowerQuadrant, List<Task>>{
    for (final quadrant in EisenhowerQuadrant.values) quadrant: [],
  };
  final now = DateTime.now();
  for (final task in tasks) {
    final dueDate = task.dueDate == null
        ? null
        : DateTime.tryParse(task.dueDate!);
    groups[classifyTask(priority: task.priority, dueDate: dueDate, now: now)]!
        .add(task);
  }
  return (
    fields: [
      MatrixBoardField(
        id: 'doFirst',
        title: 'Do first',
        tasks: groups[EisenhowerQuadrant.doFirst]!,
      ),
      MatrixBoardField(
        id: 'schedule',
        title: 'Schedule',
        tasks: groups[EisenhowerQuadrant.schedule]!,
      ),
      MatrixBoardField(
        id: 'delegate',
        title: 'Delegate',
        tasks: groups[EisenhowerQuadrant.delegate]!,
      ),
      MatrixBoardField(
        id: 'eliminate',
        title: 'Eliminate',
        tasks: groups[EisenhowerQuadrant.eliminate]!,
      ),
    ],
    unclassified: groups[EisenhowerQuadrant.unclassified]!,
  );
}
