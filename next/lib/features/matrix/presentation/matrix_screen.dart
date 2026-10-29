import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../tasks/presentation/task_form_sheet.dart';
import '../../tasks/application/task_providers.dart';
import '../../tasks/domain/task_sort_option.dart';
import '../domain/matrix_quadrant.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

import 'matrix_quadrant_view.dart';

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final sortOption = ref.watch(taskSortOptionProvider);
    final isLoaded = ref.watch(allActiveTasksProvider).hasValue;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Eisenhower Matrix',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: palette.surface.withValues(alpha: 0.95),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                textStyle: TextStyle(color: palette.text),
              ),
            ),
            child: PopupMenuButton<TaskSortOption>(
              icon: Icon(Icons.more_vert, color: palette.text),
              tooltip: 'Sorting options',
              onSelected: (option) {
                ref.read(taskSortOptionProvider.notifier).setSortOption(option);
              },
              itemBuilder: (context) => [
                for (final opt in TaskSortOption.values)
                  PopupMenuItem(
                    value: opt,
                    child: Row(
                      children: [
                        Icon(
                          opt == sortOption
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: opt == sortOption
                              ? palette.primary
                              : palette.text.withValues(alpha: 0.4),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(opt.label,
                            style:
                                TextStyle(color: palette.text, fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !isLoaded
          ? const Center(child: AppLoadingIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                            child: MatrixQuadrantView(
                          quadrant: MatrixQuadrant.doFirst,
                          palette: palette,
                          onAlarmTap: (task) =>
                              showTaskFormSheet(context,
                                  listId: task.listId,
                                  existingTask: task),
                        )),
                        const SizedBox(width: 16),
                        Expanded(
                            child: MatrixQuadrantView(
                          quadrant: MatrixQuadrant.schedule,
                          palette: palette,
                          onAlarmTap: (task) =>
                              showTaskFormSheet(context,
                                  listId: task.listId,
                                  existingTask: task),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                            child: MatrixQuadrantView(
                          quadrant: MatrixQuadrant.delegate,
                          palette: palette,
                          onAlarmTap: (task) =>
                              showTaskFormSheet(context,
                                  listId: task.listId,
                                  existingTask: task),
                        )),
                        const SizedBox(width: 16),
                        Expanded(
                            child: MatrixQuadrantView(
                          quadrant: MatrixQuadrant.eliminate,
                          palette: palette,
                          onAlarmTap: (task) =>
                              showTaskFormSheet(context,
                                  listId: task.listId,
                                  existingTask: task),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
