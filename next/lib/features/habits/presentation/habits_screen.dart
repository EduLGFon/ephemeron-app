import 'widgets/habit_tile.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';
import '../application/habit_providers.dart';
import '../domain/habit_section.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';
import '../../calendar/presentation/date_time_config_sheet.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Habits',
                style: TextStyle(
                    color: palette.text, fontWeight: FontWeight.bold)),
            _DateNavigator(palette: palette),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: habitsAsync.when(
        data: (habits) {
          if (habits.isEmpty) {
            return Center(
              child: Text(
                'No habits yet',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: palette.text),
              ),
            );
          }
          final bySection = <String, List<Habit>>{};
          for (final habit in habits) {
            bySection.putIfAbsent(habit.section, () => []).add(habit);
          }

          return CustomScrollView(
            slivers: [
              for (final entry in bySection.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Row(
                      children: [
                        Icon(HabitSection.resolve(entry.key).icon,
                            size: 22, color: palette.primary),
                        const SizedBox(width: 12),
                        Text(
                          HabitSection.resolve(entry.key).label,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: palette.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: entry.value.length,
                  itemBuilder: (context, index) {
                    final habit = entry.value[index];
                    return RepaintBoundary(
                        child: HabitTile(habit: habit, palette: palette));
                  },
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          );
        },
        loading: () => const Center(child: AppLoadingIndicator()),
        error: (error, _) => Center(
            child: Text('Could not load habits: $error',
                style: TextStyle(color: palette.text))),
      ),
    );
  }
}

class _DateNavigator extends ConsumerWidget {
  const _DateNavigator({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(habitSelectedDateProvider);
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;

    String dateText;
    if (isToday) {
      dateText = 'Today';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      dateText = '${months[selectedDate.month - 1]} ${selectedDate.day}';
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: palette.text, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(habitSelectedDateProvider.notifier).state =
                  selectedDate.subtract(const Duration(days: 1));
            },
          ),
          GestureDetector(
            onTap: () async {
              final result = await showDateTimeConfigSheet(
                context: context,
                palette: palette,
                initialStart: selectedDate,
                isRange: false,
                showAllDay: false,
                showReminder: false,
                showRepeat: false,
              );
              if (result != null) {
                ref.read(habitSelectedDateProvider.notifier).state =
                    result.start;
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                dateText,
                style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: palette.text, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              ref.read(habitSelectedDateProvider.notifier).state =
                  selectedDate.add(const Duration(days: 1));
            },
          ),
        ],
      ),
    );
  }
}
