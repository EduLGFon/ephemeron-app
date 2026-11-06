part of 'focus_screen.dart';

class _StartView extends ConsumerStatefulWidget {
  const _StartView();

  @override
  ConsumerState<_StartView> createState() => _StartViewState();
}

class _StartViewState extends ConsumerState<_StartView> {
  int _focusMin = 25;
  int _breakMin = 5;
  _FocusMode _mode = _FocusMode.focus;
  String? _taskId;
  String? _habitId;
  String? _alarmPreset = AlarmPreset.notification.id;
  bool _setupRestored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_setupRestored) {
      _setupRestored = true;
      Future.microtask(() async {
        try {
          final repo = await ref.read(settingsRepositoryProvider.future);
          if (!mounted) return;
          setState(() {
            _focusMin = repo.focusSetupMin;
            _breakMin = repo.focusBreakMin;
            // Stopwatch is not persisted; only focus/break survive restart.
            _mode = repo.focusIsBreak ? _FocusMode.breakTime : _FocusMode.focus;
            _taskId = repo.focusTaskId;
            _habitId = repo.focusHabitId;
          });
        } catch (_) {}
      });
    }
  }

  Future<void> _persistSetup() async {
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setFocusSetup(
        focusMin: _focusMin,
        breakMin: _breakMin,
        isBreak: _mode == _FocusMode.breakTime,
        taskId: () => _taskId,
        habitId: () => _habitId,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(linkableTasksProvider);
    final habitsAsync = ref.watch(linkableHabitsProvider);
    final todayAsync = ref.watch(focusTodayMinutesProvider);
    final weekAsync = ref.watch(focusWeekMinutesProvider);
    final recentAsync = ref.watch(recentFocusSessionsProvider);
    return RepaintBoundary(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_FocusMode>(
            segments: const [
              ButtonSegment(value: _FocusMode.focus, label: Text('Focus')),
              ButtonSegment(value: _FocusMode.breakTime, label: Text('Break')),
              ButtonSegment(
                value: _FocusMode.stopwatch,
                label: Text('Stopwatch'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) {
              setState(() => _mode = s.single);
              _persistSetup();
            },
          ),
          const SizedBox(height: 8),
          if (_mode != _FocusMode.stopwatch) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final m
                    in (_mode == _FocusMode.breakTime
                        ? _breakPresets
                        : _focusPresets))
                  ChoiceChip(
                    label: Text('$m min'),
                    selected:
                        (_mode == _FocusMode.breakTime
                            ? _breakMin
                            : _focusMin) ==
                        m,
                    onSelected: (_) {
                      setState(() {
                        if (_mode == _FocusMode.breakTime) {
                          _breakMin = m;
                        } else {
                          _focusMin = m;
                        }
                      });
                      _persistSetup();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          tasksAsync.maybeWhen(
            data: (tasks) => DropdownButtonFormField<String?>(
              initialValue: _taskId,
              decoration: const InputDecoration(
                labelText: 'Link task (optional)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final t in tasks.take(50))
                  DropdownMenuItem<String?>(value: t.id, child: Text(t.title)),
              ],
              onChanged: (v) {
                setState(() => _taskId = v);
                _persistSetup();
              },
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
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None'),
                ),
                for (final h in habits)
                  DropdownMenuItem<String?>(value: h.id, child: Text(h.name)),
              ],
              onChanged: (v) {
                setState(() => _habitId = v);
                _persistSetup();
              },
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          if (_mode != _FocusMode.stopwatch) ...[
            AlarmPresetPicker(
              value: _alarmPreset,
              onChanged: (v) => setState(
                () => _alarmPreset = v,
              ), // alarm preset is per-session, not persisted
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              _mode == _FocusMode.stopwatch
                  ? 'Start stopwatch'
                  : 'Start ${_mode == _FocusMode.breakTime ? _breakMin : _focusMin} min ${_mode == _FocusMode.breakTime ? 'break' : 'focus'}',
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
      ),
    );
  }

  Future<void> _start() async {
    final isStopwatch = _mode == _FocusMode.stopwatch;
    // Moment of need: the end-of-phase alarm needs notifications, and
    // clock presets need exact-alarm access. Advisory only. Stopwatch has
    // no end alarm, so it asks for nothing.
    final preset = AlarmPreset.tryParse(_alarmPreset);
    if (!isStopwatch) {
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset?.needsAlarmClock ?? false,
        fullScreen: preset?.usesFullScreen ?? false,
      );
      if (!mounted) return;
    }
    final repo = ref.read(focusRepositoryProvider);
    final id = await repo.startSession(
      taskId: _taskId,
      habitId: _habitId,
      durationMin: isStopwatch
          ? null
          : (_mode == _FocusMode.breakTime ? _breakMin : _focusMin),
      phase: isStopwatch
          ? 'stopwatch'
          : (_mode == _FocusMode.breakTime ? 'break' : 'focus'),
      alarmPreset: isStopwatch ? null : _alarmPreset,
    );
    final session = await repo.currentSession();
    if (session != null && session.id == id) {
      // No-op for stopwatch sessions (targetEndUtc is null).
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
