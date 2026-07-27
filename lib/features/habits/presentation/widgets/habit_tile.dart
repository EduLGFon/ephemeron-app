import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_palettes.dart';
import '../../../../data/local/database.dart';
import '../../application/habit_providers.dart';
import '../../data/habit_repository.dart';
import '../habit_form_sheet.dart';
import 'habit_progress_indicator.dart';

class HabitTile extends ConsumerWidget {
  const HabitTile({super.key, required this.habit, required this.palette});

  final Habit habit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(habitMetricsProvider(habit.id));
    final repo = ref.read(habitRepositoryProvider);
    final logsAsync = ref.watch(habitLogsProvider(habit.id));

    final selectedDate = ref.watch(habitSelectedDateProvider);
    final selectedDateNormalized =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final selectedDateLog =
        _findLogForDate(logsAsync.value, selectedDateNormalized);

    final isCompleted = habit.goalType == 'binary'
        ? (selectedDateLog?.isCompleted ?? false)
        : ((selectedDateLog?.amount ?? 0) >=
            (habit.goalAmount ?? double.infinity));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted
              ? palette.primary.withValues(alpha: 0.5)
              : palette.text.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showHabitFormSheet(context, existingHabit: habit),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  _buildActionWidget(repo, selectedDateLog, isCompleted,
                      context, ref, selectedDateNormalized),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          habit.name,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            decoration:
                                isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 6),
                        metricsAsync.when(
                          data: (metrics) => HabitProgressIndicator(
                            metrics: metrics,
                            palette: palette,
                          ),
                          loading: () => const SizedBox(height: 16),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  if (habit.goalType == 'amount' && habit.goalAmount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: palette.text.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_formatAmount(selectedDateLog?.amount ?? 0)} / ${_formatAmount(habit.goalAmount!)} ${habit.goalUnit ?? ''}',
                        style: TextStyle(
                            color: palette.text.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionWidget(
      HabitRepository repo,
      HabitLog? selectedDateLog,
      bool isCompleted,
      BuildContext context,
      WidgetRef ref,
      DateTime selectedDate) {
    if (habit.goalType == 'binary') {
      return GestureDetector(
        onTap: () => repo.toggleBinary(habit.id, selectedDate),
        onDoubleTap: () => repo.resetLog(habit.id, selectedDate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted ? palette.primary : Colors.transparent,
            border: Border.all(
              color: isCompleted
                  ? palette.primary
                  : palette.text.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: isCompleted
              ? Icon(Icons.check, size: 20, color: palette.background)
              : null,
        ),
      );
    } else {
      return GestureDetector(
        onLongPress: () =>
            _logAmount(context, ref, habit, selectedDateLog, selectedDate),
        onTap: () => repo.quickLog(habit.id, selectedDate),
        onDoubleTap: () => repo.resetLog(habit.id, selectedDate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCompleted
                ? palette.primary
                : palette.primary.withValues(alpha: 0.1),
          ),
          child: isCompleted
              ? Icon(Icons.check, color: palette.background, size: 20)
              : Icon(Icons.add, color: palette.primary, size: 20),
        ),
      );
    }
  }

  String _formatAmount(double amount) {
    return amount.truncateToDouble() == amount
        ? amount.toInt().toString()
        : amount.toStringAsFixed(1);
  }

  HabitLog? _findLogForDate(List<HabitLog>? logs, DateTime dateNormalized) {
    if (logs == null) return null;
    for (final log in logs) {
      if (DateTime(log.date.year, log.date.month, log.date.day) ==
          dateNormalized) {
        return log;
      }
    }
    return null;
  }

  Future<void> _logAmount(
    BuildContext context,
    WidgetRef ref,
    Habit habit,
    HabitLog? selectedDateLog,
    DateTime selectedDate,
  ) async {
    final controller =
        TextEditingController(text: selectedDateLog?.amount.toString() ?? '');
    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
            '${habit.name}${habit.goalUnit != null ? ' (${habit.goalUnit})' : ''}',
            style: TextStyle(color: palette.text)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: palette.text),
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: habit.goalUnit,
            labelStyle: TextStyle(color: palette.text.withValues(alpha: 0.6)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Passing a negative number to indicate a reset
              Navigator.pop(context, -1.0);
            },
            child: Text('Reset',
                style:
                    TextStyle(color: Colors.redAccent.withValues(alpha: 0.8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: palette.text.withValues(alpha: 0.6))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: palette.background),
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log'),
          ),
        ],
      ),
    );

    if (result == null) return;

    final repo = ref.read(habitRepositoryProvider);
    if (result == -1.0) {
      await repo.resetLog(habit.id, selectedDate);
      return;
    }

    final goalAmount = habit.goalAmount ?? double.infinity;
    await repo.logProgress(
      habit.id,
      date: selectedDate,
      amount: result,
      isCompleted: result >= goalAmount,
    );
  }
}
