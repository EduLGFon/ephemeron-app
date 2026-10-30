// Focus screen: timestamp-based timer (elapsed computed per frame
// while visible), one native end alarm, stats, session history.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/platform/system_launcher.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../../alarms/data/alarm_scheduler.dart';
import '../../habits/application/habits_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../application/focus_providers.dart';
import 'focus_stats_screen.dart';

const _focusPresets = [15, 25, 50];
const _breakPresets = [5, 10, 15];

Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
  final sessions = ref.read(recentFocusSessionsProvider).value ?? const [];
  final buf = StringBuffer('start,end,minutes,phase,note\n');
  for (final s in sessions) {
    buf.writeln(
      '${s.startUtc},${s.endUtc ?? ''},${s.endUtc == null ? '' : ((s.endUtc! - s.startUtc) / 60000).floor()},${s.phase ?? ''},${(s.note ?? '').replaceAll(',', ';')}',
    );
  }
  await Clipboard.setData(ClipboardData(text: buf.toString()));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Focus CSV copied to clipboard')),
    );
  }
}

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentFocusSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: 'Monthly stats',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FocusStatsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export CSV',
            onPressed: () => _exportCsv(context, ref),
          ),
        ],
      ),
      body: currentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: OutlinedButton(
            onPressed: () => ref.invalidate(currentFocusSessionProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (session) => session == null
            ? const _StartView()
            : _RunningView(session: session),
      ),
    );
  }
}

void _refresh(WidgetRef ref) {
  ref.invalidate(currentFocusSessionProvider);
  ref.invalidate(focusTodayMinutesProvider);
  ref.invalidate(focusWeekMinutesProvider);
}

int _requestCode(String id) => id.hashCode & 0x7fffffff;

Future<void> _scheduleEndAlarm(FocusSession s) {
  final target = s.targetEndUtc;
  if (target == null) return Future.value();
  return AlarmScheduler.schedule(
    requestCode: _requestCode(s.id),
    fireAtUtcMs: target,
    useAlarmClock: true,
    title: 'Focus session complete',
    sourceType: 'focus',
    sourceId: s.id,
  );
}

class _StartView extends ConsumerStatefulWidget {
  const _StartView();

  @override
  ConsumerState<_StartView> createState() => _StartViewState();
}

class _StartViewState extends ConsumerState<_StartView> {
  int _focusMin = 25;
  int _breakMin = 5;
  bool _isBreak = false;
  String? _taskId;
  String? _habitId;

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(linkableTasksProvider);
    final habitsAsync = ref.watch(linkableHabitsProvider);
    final todayAsync = ref.watch(focusTodayMinutesProvider);
    final weekAsync = ref.watch(focusWeekMinutesProvider);
    final recentAsync = ref.watch(recentFocusSessionsProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Focus')),
            ButtonSegment(value: true, label: Text('Break')),
          ],
          selected: {_isBreak},
          onSelectionChanged: (s) => setState(() => _isBreak = s.single),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final m in (_isBreak ? _breakPresets : _focusPresets))
              ChoiceChip(
                label: Text('$m min'),
                selected: (_isBreak ? _breakMin : _focusMin) == m,
                onSelected: (_) => setState(() {
                  if (_isBreak) {
                    _breakMin = m;
                  } else {
                    _focusMin = m;
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        tasksAsync.maybeWhen(
          data: (tasks) => DropdownButtonFormField<String?>(
            initialValue: _taskId,
            decoration: const InputDecoration(
              labelText: 'Link task (optional)',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final t in tasks.take(50))
                DropdownMenuItem<String?>(value: t.id, child: Text(t.title)),
            ],
            onChanged: (v) => setState(() => _taskId = v),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        habitsAsync.maybeWhen(
          data: (habits) => DropdownButtonFormField<String?>(
            initialValue: _habitId,
            decoration: const InputDecoration(
              labelText: 'Link habit (optional)',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final h in habits)
                DropdownMenuItem<String?>(value: h.id, child: Text(h.name)),
            ],
            onChanged: (v) => setState(() => _habitId = v),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            'Start ${_isBreak ? _breakMin : _focusMin} min ${_isBreak ? 'break' : 'focus'}',
          ),
        ),
        const SizedBox(height: 16),
        todayAsync.maybeWhen(
          data: (min) => Text(
            'Today: ${_formatMin(min)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        weekAsync.maybeWhen(
          data: (days) => _WeekBars(days: days),
          orElse: () => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        recentAsync.maybeWhen(
          data: (sessions) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent', style: Theme.of(context).textTheme.titleSmall),
              for (final s in sessions.take(10)) _SessionTile(session: s),
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Future<void> _start() async {
    final repo = ref.read(focusRepositoryProvider);
    final id = await repo.startSession(
      taskId: _taskId,
      habitId: _habitId,
      durationMin: _isBreak ? _breakMin : _focusMin,
      phase: _isBreak ? 'break' : 'focus',
    );
    final session = await repo.currentSession();
    if (session != null && session.id == id) {
      await _scheduleEndAlarm(session);
      await SystemLauncher.startFocusChronometer(
        '${session.phase ?? 'focus'} session',
        session.startUtc,
      );
      try {
        final settings = await ref.read(settingsRepositoryProvider.future);
        if (settings.focusDnd) await SystemLauncher.setDnd(true);
      } catch (_) {
        // DND is best-effort; the session runs regardless.
      }
    }
    _refresh(ref);
  }
}

class _RunningView extends ConsumerStatefulWidget {
  const _RunningView({required this.session});

  final FocusSession session;

  @override
  ConsumerState<_RunningView> createState() => _RunningViewState();
}

class _RunningViewState extends ConsumerState<_RunningView> {
  Timer? _ticker;
  final ValueNotifier<int> _now = ValueNotifier<int>(
    DateTime.now().toUtc().millisecondsSinceEpoch,
  );

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _now.value = DateTime.now().toUtc().millisecondsSinceEpoch;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _now.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _now,
      builder: (context, now, _) {
        final target = widget.session.targetEndUtc;
        final elapsedMin = ((now - widget.session.startUtc) / 60000).floor();
        final remainingMs = target == null ? 0 : target - now;
        final finished = target != null && remainingMs <= 0;
        final remaining = finished
            ? '00:00'
            : '${(remainingMs ~/ 60000).toString().padLeft(2, '0')}:${((remainingMs % 60000) ~/ 1000).toString().padLeft(2, '0')}';
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isAbandoned(now))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Recovered after app restart. Finishing keeps $elapsedMin min.',
                    ),
                  ),
                ),
              if (finished)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Time is up - $elapsedMin min elapsed.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Center(
                child: Semantics(
                  label: 'Focus time remaining: $remaining',
                  child: Text(
                    remaining,
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                ),
              ),
              Center(
                child: Text(
                  '${widget.session.phase ?? 'focus'} - $elapsedMin min elapsed',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _finish(context, ref, elapsedMin),
                icon: const Icon(Icons.stop),
                label: Text(finished ? 'Complete' : 'Finish'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _discard(context, ref),
                child: const Text('Discard session'),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isAbandoned(int now) => now - widget.session.startUtc > 12 * 3600000;

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    int elapsedMin,
  ) async {
    final repo = ref.read(focusRepositoryProvider);
    final note = await _askNote(context);
    if (!context.mounted) return;
    final kept = await repo.finishSession(widget.session.id, note: note);
    await AlarmScheduler.cancel(_requestCode(widget.session.id));
    await SystemLauncher.stopFocusChronometer();
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      if (settings.focusDnd) await SystemLauncher.setDnd(false);
    } catch (_) {}
    final habitId = widget.session.habitId;
    if (habitId != null && kept > 0 && context.mounted) {
      await _creditHabit(context, ref, habitId, kept);
    }
    _refresh(ref);
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(focusRepositoryProvider);
    await repo.deleteSession(widget.session.id);
    await AlarmScheduler.cancel(_requestCode(widget.session.id));
    await SystemLauncher.stopFocusChronometer();
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      if (settings.focusDnd) await SystemLauncher.setDnd(false);
    } catch (_) {}
    _refresh(ref);
  }
}

Future<void> _creditHabit(
  BuildContext context,
  WidgetRef ref,
  String habitId,
  int kept,
) async {
  final repo = ref.read(habitRepositoryProvider);
  final today = habitDateKey(DateTime.now());
  await repo.logDone(habitId, today);
  ref.invalidate(habitStreakProvider(habitId));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Credited $kept min to habit.'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          repo.backfill(habitId, today, 0, false);
          ref.invalidate(habitStreakProvider(habitId));
        },
      ),
    ),
  );
}

Future<String?> _askNote(BuildContext context) async {
  // Not disposed: disposal would race the dialog pop transition, which
  // rebuilds the text field for a few frames after pop.
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Session note (optional)'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Note'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

String _formatMin(int min) {
  if (min < 60) return '$min min';
  return '${min ~/ 60}h ${min % 60}m';
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});

  final List<int> days;

  @override
  Widget build(BuildContext context) {
    final max = days.fold<int>(1, (a, b) => b > a ? b : a);
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      height: 60 * (days[i] / max),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Text(
                      '${days[i]}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      session.startUtc,
      isUtc: true,
    ).toLocal();
    final end = session.endUtc == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            session.endUtc!,
            isUtc: true,
          ).toLocal();
    final min = end == null
        ? null
        : ((session.endUtc! - session.startUtc) / 60000).floor();
    return ListTile(
      dense: true,
      title: Text(
        '${session.phase ?? 'focus'} - ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
        '${min == null ? '' : ' - ${_formatMin(min)}'}',
      ),
      subtitle: session.note == null || session.note!.isEmpty
          ? null
          : Text(session.note!),
    );
  }
}
