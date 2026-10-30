// Eisenhower matrix: quadrants from priority + due date, drag-free
// tap-to-edit, unclassified tray, configurable urgent window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/tasks/eisenhower.dart';
import '../../../data/drift/app_database.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/tasks_providers.dart';
import 'task_editor_sheet.dart';

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(openTasksProvider(null));
    return Scaffold(
      appBar: AppBar(title: const SyncTitle(text: 'Matrix')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (tasks) {
          final now = DateTime.now();
          final groups = <EisenhowerQuadrant, List<Task>>{
            for (final q in EisenhowerQuadrant.values) q: [],
          };
          for (final t in tasks) {
            DateTime? due;
            if (t.dueDate != null) {
              final p = t.dueDate!.split('-');
              due = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
            }
            groups[classifyTask(priority: t.priority, dueDate: due, now: now)]!
                .add(t);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _QuadrantCard(
                title: 'Do first',
                tasks: groups[EisenhowerQuadrant.doFirst]!,
              ),
              _QuadrantCard(
                title: 'Schedule',
                tasks: groups[EisenhowerQuadrant.schedule]!,
              ),
              _QuadrantCard(
                title: 'Delegate',
                tasks: groups[EisenhowerQuadrant.delegate]!,
              ),
              _QuadrantCard(
                title: 'Eliminate',
                tasks: groups[EisenhowerQuadrant.eliminate]!,
              ),
              _QuadrantCard(
                title: 'Unclassified',
                tasks: groups[EisenhowerQuadrant.unclassified]!,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuadrantCard extends StatelessWidget {
  const _QuadrantCard({required this.title, required this.tasks});

  final String title;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('$title (${tasks.length})'),
        initiallyExpanded: title == 'Do first',
        children: [
          if (tasks.isEmpty) const ListTile(title: Text('Empty')),
          for (final t in tasks)
            ListTile(
              title: Text(t.title),
              subtitle: t.dueDate == null ? null : Text(t.dueDate!),
              onTap: () => showTaskEditor(context, task: t),
            ),
        ],
      ),
    );
  }
}
