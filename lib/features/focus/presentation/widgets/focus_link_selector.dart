import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_palettes.dart';
import '../../../habits/application/habit_providers.dart';
import '../../../tasks/application/task_providers.dart';
import '../../../tasks/domain/smart_list_type.dart';
import '../../application/focus_timer_controller.dart';
import '../../application/focus_timer_state.dart';

class FocusLinkSelector extends ConsumerWidget {
  const FocusLinkSelector({
    super.key,
    required this.state,
    required this.controller,
    required this.palette,
  });

  final FocusTimerState state;
  final FocusTimerController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isRunning) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          state.linkedTaskId != null
              ? 'Linked to a task'
              : state.linkedHabitId != null
                  ? 'Linked to a habit'
                  : 'Not linked to a task or habit',
          style: TextStyle(color: palette.text.withValues(alpha: 0.8)),
        ),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.primary,
        side: BorderSide(color: palette.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.link),
      label: Text(
        state.linkedTaskId != null || state.linkedHabitId != null
            ? 'Change link'
            : 'Link to task/habit',
      ),
      onPressed: () => _showLinkPicker(context, ref),
    );
  }

  Future<void> _showLinkPicker(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(
            child: Consumer(builder: (context, ref, child) {
              final tasksAsync =
                  ref.watch(smartListProvider(SmartListType.today));
              final habitsAsync = ref.watch(habitsProvider);

              return ListView(
                shrinkWrap: true,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text('None', style: TextStyle(color: palette.text)),
                    onTap: () {
                      controller.setLinkedTask(null);
                      Navigator.pop(context);
                    },
                  ),
                  if (habitsAsync.value case final habits?)
                    for (final habit in habits)
                      ListTile(
                        leading:
                            Icon(Icons.repeat_outlined, color: palette.text),
                        title: Text(habit.name,
                            style: TextStyle(color: palette.text)),
                        onTap: () {
                          controller.setLinkedHabit(habit.id);
                          Navigator.pop(context);
                        },
                      ),
                  if (tasksAsync.value case final tasks?)
                    for (final task in tasks)
                      ListTile(
                        leading:
                            Icon(Icons.checklist_outlined, color: palette.text),
                        title: Text(task.title,
                            style: TextStyle(color: palette.text)),
                        onTap: () {
                          controller.setLinkedTask(task.id);
                          Navigator.pop(context);
                        },
                      ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
