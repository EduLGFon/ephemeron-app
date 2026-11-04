// Habits screen: 7-day navigator, sections, one-tap logging,
// skip, streaks, archive with undo.
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
              label: Text('${DeviceDateFormat.e(context).format(d)} ${d.day}'),
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
    final storeAsync = ref.watch(habitTimerStoreProvider);
    return logsAsync.maybeWhen(
      data: (logs) {
        final log = _logFor(logs, day);
        final done = log?.done ?? false;
        final skipped = log?.skipped ?? false;
        final amount = log?.amount ?? 0.0;
        final goal = habit.goalAmount ?? 0.0;
        final hasGoal = goal > 0;
        final step = habit.increment ?? 1.0;
        final repo = ref.read(habitRepositoryProvider);
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
            data: (st) {
              final progress = hasGoal
                  ? '${_fmt(amount)}/${_fmt(goal)} ${habit.unit ?? ''}'.trim()
                  : null;
              final streakText = skipped
                  ? 'Skipped - streak ${st.current} - best ${st.best}'
                  : 'Streak ${st.current} - best ${st.best}';
              if (progress == null) return Text(streakText);
              return Text('$progress  $streakText');
            },
            orElse: () => hasGoal
                ? Text(
                    '${_fmt(amount)}/${_fmt(goal)} ${habit.unit ?? ''}'.trim(),
                  )
                : null,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasGoal)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  icon: const Icon(Icons.add),
                  tooltip: 'Add ${_fmt(step)}',
                  onPressed: () async {
                    await repo.addAmount(habit.id, day, step);
                    ref.invalidate(habitStreakProvider(habit.id));
                  },
                ),
              if (isMinuteUnit(habit.unit) && storeAsync.hasValue)
                _HabitTimerControl(
                  habit: habit,
                  day: day,
                  store: storeAsync.value!,
                  repo: repo,
                  onMessage: (m) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(m)));
                    }
                  },
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: Icon(
                  skipped ? Icons.play_arrow_outlined : Icons.pause_outlined,
                ),
                tooltip: skipped ? 'Unskip' : 'Skip day',
                color: skipped ? Theme.of(context).colorScheme.primary : null,
                onPressed: () => _toggleSkip(context, ref, !skipped),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
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

class _HabitTimerControl extends StatefulWidget {
  const _HabitTimerControl({
    required this.habit,
    required this.day,
    required this.store,
    required this.repo,
    required this.onMessage,
  });

  final Habit habit;
  final String day;
  final HabitTimerStore store;
  final HabitRepository repo;
  final void Function(String) onMessage;

  @override
  State<_HabitTimerControl> createState() => _HabitTimerControlState();
}

class _HabitTimerControlState extends State<_HabitTimerControl> {
  Timer? _timer;
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );

  @override
  void initState() {
    super.initState();
    widget.store.active.addListener(_onActiveChanged);
    _sync();
  }

  @override
  void dispose() {
    widget.store.active.removeListener(_onActiveChanged);
    _timer?.cancel();
    _elapsed.dispose();
    super.dispose();
  }

  void _onActiveChanged() => _sync();

  void _sync() {
    _timer?.cancel();
    final t = widget.store.active.value;
    if (t != null && t.habitId == widget.habit.id) {
      _updateElapsed();
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateElapsed(),
      );
    } else {
      _elapsed.value = Duration.zero;
    }
  }

  void _updateElapsed() {
    final t = widget.store.active.value;
    if (t == null) return;
    _elapsed.value = timerElapsed(
      startedAtMs: t.startedAtMs,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool get _isRunning => widget.store.active.value?.habitId == widget.habit.id;

  Future<void> _toggle() async {
    if (_isRunning) {
      final t = widget.store.active.value!;
      final elapsed = timerElapsed(
        startedAtMs: t.startedAtMs,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      await widget.repo.addAmount(
        widget.habit.id,
        t.dayKey,
        elapsedMinutes(elapsed),
      );
      await widget.store.clear();
    } else {
      if (widget.day != habitTodayKey()) {
        widget.onMessage('Timer can only start for today.');
        return;
      }
      if (widget.store.active.value != null) {
        widget.onMessage('Another habit timer is already running.');
        return;
      }
      await widget.store.start(
        widget.habit.id,
        widget.day,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: _elapsed,
      builder: (_, dur, _) {
        if (_isRunning) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatElapsed(dur)),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 20,
                icon: const Icon(Icons.stop),
                tooltip: 'Stop timer',
                onPressed: _toggle,
              ),
            ],
          );
        }
        return IconButton(
          visualDensity: VisualDensity.compact,
          iconSize: 20,
          icon: const Icon(Icons.play_arrow),
          tooltip: 'Start timer',
          onPressed: _toggle,
        );
      },
    );
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
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
