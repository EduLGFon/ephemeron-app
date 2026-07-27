import 'package:flutter/material.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import 'task_tile.dart';

class CompletedTasksSection extends StatelessWidget {
  const CompletedTasksSection({
    super.key,
    required this.completedTasks,
    required this.palette,
  });

  final List<Task> completedTasks;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (completedTasks.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverToBoxAdapter(
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            expansionTileTheme: ExpansionTileThemeData(
              textColor: palette.primary,
              iconColor: palette.primary,
              collapsedIconColor: palette.text.withValues(alpha: 0.5),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              title: Text(
                'Completed (\${completedTasks.length})',
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              childrenPadding: EdgeInsets.zero,
              children: [
                for (final task in completedTasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: RepaintBoundary(child: TaskTile(task: task, palette: palette)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
