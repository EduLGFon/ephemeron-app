// Habits screen: 7-day navigator, sections, one-tap logging,
// skip, streaks, archive with undo.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:ephemeron/core/ui/empty_state.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../../sync/application/pending_operations.dart';
import '../application/habits_providers.dart';
import 'habit_editor_sheet.dart';

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

class _DayStrip extends StatefulWidget {
  const _DayStrip({required this.selected, required this.onSelect});

  final String selected;
  final void Function(String day) onSelect;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DayStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final d in days) ...[
            ChoiceChip(
              label: Text(
                '${DeviceDateFormat.e(context).format(d)} ${d.day}',
              ),
              selected: habitDateKey(d) == widget.selected,
              onSelected: (_) => widget.onSelect(habitDateKey(d)),
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
    final items = <Widget>[];
    for (final key in orderedKeys) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            sectionName(key),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      items.addAll(bySection[key]!.map((h) => _HabitTile(habit: h)));
    }
    return RepaintBoundary(
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
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
    final pending = ref.read(pendingOperationsProvider);
    final wasArchived = habit.archived;
    final opId = await pending.scheduleHabitArchive(habit.id, !wasArchived);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(wasArchived ? 'Habit unarchived.' : 'Habit archived.'),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => pending.cancel(opId),
        ),
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
