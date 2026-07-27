import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_sort_option.dart';
import '../application/matrix_providers.dart';
import '../domain/matrix_quadrant.dart';
import 'matrix_task_tile.dart';

class MatrixQuadrantView extends ConsumerStatefulWidget {
  const MatrixQuadrantView(
      {super.key,
      required this.quadrant,
      required this.palette,
      required this.onAlarmTap});

  final MatrixQuadrant quadrant;
  final AppPalette palette;
  final void Function(Task) onAlarmTap;

  @override
  ConsumerState<MatrixQuadrantView> createState() => _MatrixQuadrantViewState();
}

class _MatrixQuadrantViewState extends ConsumerState<MatrixQuadrantView> {
  @override
  Widget build(BuildContext context) {
    final pendingTasksAsync =
        ref.watch(pendingMatrixTasksProvider(widget.quadrant));
    final completedTasksAsync =
        ref.watch(completedMatrixTasksProvider(widget.quadrant));
    final pendingTasks = pendingTasksAsync.value ?? [];
    final completedTasks = completedTasksAsync.value ?? [];
    final color = widget.quadrant.color;
    final totalCount = pendingTasks.length + completedTasks.length;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: widget.palette.surface
              .withValues(alpha: widget.palette.isAmoled ? 1.0 : 0.5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.quadrant.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalCount',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.quadrant.description,
                  style: TextStyle(
                      color: widget.palette.text.withValues(alpha: 0.6),
                      fontSize: 12),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: (pendingTasks.isEmpty && completedTasks.isEmpty)
                      ? Center(
                          child: Icon(
                            Icons.task_alt,
                            color: color.withValues(alpha: 0.2),
                            size: 48,
                          ),
                        )
                      : CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            if (pendingTasks.isNotEmpty)
                              SliverReorderableList(
                                itemCount: pendingTasks.length,
                                onReorder: (oldIdx, newIdx) async {
                                  if (oldIdx < newIdx) {
                                    newIdx -= 1;
                                  }
                                  final mutableList =
                                      List<Task>.from(pendingTasks);
                                  final item = mutableList.removeAt(oldIdx);
                                  mutableList.insert(newIdx, item);

                                  ref
                                      .read(taskSortOptionProvider.notifier)
                                      .setSortOption(TaskSortOption.custom);

                                  final ids =
                                      mutableList.map((t) => t.id).toList();
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
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: RepaintBoundary(
                                        child: MatrixTaskTile(
                                          task: task,
                                          quadrant: widget.quadrant,
                                          palette: widget.palette,
                                          onAlarmTap: widget.onAlarmTap,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            if (completedTasks.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: ExpansionTile(
                                      title: Text(
                                        'Completed (${completedTasks.length})',
                                        style: TextStyle(
                                          color: widget.palette.text
                                              .withValues(alpha: 0.5),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      trailing: const SizedBox.shrink(),
                                      tilePadding: EdgeInsets.zero,
                                      childrenPadding: EdgeInsets.zero,
                                      children: [
                                        for (final task in completedTasks)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 8.0),
                                            child: RepaintBoundary(
                                              child: MatrixTaskTile(
                                                task: task,
                                                quadrant: widget.quadrant,
                                                palette: widget.palette,
                                                onAlarmTap: widget.onAlarmTap,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
