// Habits screen: 7-day navigator, sections, one-tap logging,
// skip, streaks, archive with undo.
//
// The screen is a single Dart library split into `part` files under
// presentation/habits_screen/ so each widget stays focused while private
// members remain shared within the screen. The entry point and import
// path are unchanged for existing importers.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/empty_state.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../../../domain/habits/habit_timer.dart';
import '../../sync/application/pending_operations.dart';
import '../application/habits_providers.dart';
import '../../../data/repositories/habit_repository.dart';
import '../../../data/services/habit_timer_store.dart';
import 'habit_editor_sheet.dart';

part 'habits_screen/day_strip.dart';
part 'habits_screen/habit_list.dart';
part 'habits_screen/habit_tile.dart';
part 'habits_screen/habit_timer_control.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(showArchivedHabitsProvider);
    final habitsAsync = ref.watch(habitsProvider(archived));
    final sectionsAsync = ref.watch(habitSectionsProvider);
    final selectedDay = ref.watch(selectedHabitDayProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            tooltip: archived ? 'Hide archived' : 'Show archived',
            onPressed: () =>
                ref.read(showArchivedHabitsProvider.notifier).toggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          _DayStrip(
            selected: selectedDay,
            onSelect: (d) =>
                ref.read(selectedHabitDayProvider.notifier).select(d),
          ),
          Expanded(
            child: habitsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => _ErrorState(
                onRetry: () => ref.invalidate(habitsProvider(archived)),
              ),
              data: (habits) {
                if (habits.isEmpty) {
                  return EmptyState(
                    icon: Icons.repeat_outlined,
                    title: archived ? 'No archived habits.' : 'No habits yet.',
                    actionLabel: archived ? null : 'Add habit',
                    onAction: archived ? null : () => showHabitEditor(context),
                  );
                }
                return sectionsAsync.maybeWhen(
                  data: (sections) =>
                      _HabitList(habits: habits, sections: sections),
                  orElse: () => _HabitList(habits: habits, sections: const []),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'habitsFab',
        onPressed: () => showHabitEditor(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Could not load habits.'),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
