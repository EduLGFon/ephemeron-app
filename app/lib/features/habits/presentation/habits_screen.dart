// Habits screen: 7-day navigator, sections, one-tap logging,
// skip, streaks, archive with undo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../application/habits_providers.dart';
import 'habit_editor_sheet.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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
                  return _EmptyState(archived: archived);
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

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.selected, required this.onSelect});

  final String selected;
  final void Function(String day) onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final d in days) ...[
            ChoiceChip(
              label: Text('${_weekdayLabels[d.weekday - 1]} ${d.day}'),
              selected: habitDateKey(d) == selected,
              onSelected: (_) => onSelect(habitDateKey(d)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _HabitList extends StatelessWidget {
  const _HabitList({required this.habits, required this.sections});

  final List<Habit> habits;
  final List<HabitSection> sections;

  @override
  Widget build(BuildContext context) {
    final bySection = <String?, List<Habit>>{};
    for (final h in habits) {
      bySection.putIfAbsent(h.sectionId, () => []).add(h);
    }
    String sectionName(String? id) {
      if (id == null) return 'No section';
      for (final s in sections) {
        if (s.id == id) return s.name;
      }
      return 'No section';
    }

    final orderedKeys = [
      ...sections.map((s) => s.id).where(bySection.containsKey),
      if (bySection.containsKey(null)) null,
      ...bySection.keys.where(
        (k) => k != null && !sections.any((s) => s.id == k),
      ),
    ];
    return ListView(
      children: [
        for (final key in orderedKeys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              sectionName(key),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final h in bySection[key]!) _HabitTile(habit: h),
        ],
      ],
    );
  }
}

HabitLog? _logFor(List<HabitLog> logs, String day) {
  for (final l in logs) {
    if (l.dayKey == day) return l;
  }
  return null;
}

class _HabitTile extends ConsumerWidget {
  const _HabitTile({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(selectedHabitDayProvider);
    final logsAsync = ref.watch(habitLogsProvider(habit.id));
    final streakAsync = ref.watch(habitStreakProvider(habit.id));
    return logsAsync.maybeWhen(
      data: (logs) {
        final log = _logFor(logs, day);
        final done = log?.done ?? false;
        final skipped = log?.skipped ?? false;
        return ListTile(
          leading: Checkbox(
            value: done,
            onChanged: (_) => _toggleDone(context, ref, !done),
          ),
          title: Text(
            habit.name,
            style: done
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
          subtitle: streakAsync.maybeWhen(
            data: (s) => Text(
              skipped
                  ? 'Skipped - streak ${s.current} - best ${s.best}'
                  : 'Streak ${s.current} - best ${s.best}',
            ),
            orElse: () => null,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  skipped ? Icons.play_arrow_outlined : Icons.pause_outlined,
                ),
                tooltip: skipped ? 'Unskip' : 'Skip day',
                color: skipped ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => _toggleSkip(context, ref, !skipped),
              ),
              IconButton(
                icon: Icon(
                  habit.archived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                ),
                tooltip: habit.archived ? 'Unarchive' : 'Archive',
                onPressed: () => _toggleArchive(context, ref),
              ),
            ],
          ),
          onTap: () => showHabitEditor(context, habit: habit),
        );
      },
      orElse: () => ListTile(title: Text(habit.name)),
    );
  }

  Future<void> _toggleDone(
    BuildContext context,
    WidgetRef ref,
    bool done,
  ) async {
    final repo = ref.read(habitRepositoryProvider);
    final day = ref.read(selectedHabitDayProvider);
    if (done) {
      await repo.logDone(habit.id, day);
    } else {
      await repo.backfill(habit.id, day, 0, false);
    }
    ref.invalidate(habitStreakProvider(habit.id));
  }

  Future<void> _toggleSkip(
    BuildContext context,
    WidgetRef ref,
    bool skipped,
  ) async {
    final repo = ref.read(habitRepositoryProvider);
    await repo.setSkipped(
      habit.id,
      ref.read(selectedHabitDayProvider),
      skipped,
    );
    ref.invalidate(habitStreakProvider(habit.id));
  }

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(habitRepositoryProvider);
    final wasArchived = habit.archived;
    await repo.archiveHabit(habit.id, !wasArchived);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasArchived ? 'Habit unarchived.' : 'Habit archived.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.archiveHabit(habit.id, wasArchived),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.archived});

  final bool archived;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.repeat_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            archived ? 'No archived habits.' : 'No habits yet.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!archived) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => showHabitEditor(context),
              child: const Text('Add habit'),
            ),
          ],
        ],
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
