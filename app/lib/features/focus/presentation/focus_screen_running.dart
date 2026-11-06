part of 'focus_screen.dart';

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
  bool _completionNotified = false;

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

  bool _handlingPendingNext = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingFocusNextProvider, (prev, next) {
      if (next == null || _handlingPendingNext || !mounted) return;
      final target = widget.session.targetEndUtc;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final finished = target != null && now >= target;
      if (!finished) return;
      _handlingPendingNext = true;
      ref.read(pendingFocusNextProvider.notifier).set(null);
      final elapsedMin = ((now - widget.session.startUtc) / msPerMinute)
          .floor();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _completeAndStartPhase(
          context,
          ref,
          elapsedMin,
          startBreak: next == 'break',
        );
        _handlingPendingNext = false;
      });
    });
    return ValueListenableBuilder<int>(
      valueListenable: _now,
      builder: (context, now, _) {
        final target = widget.session.targetEndUtc;
        final isStopwatch = target == null;
        final elapsedMs = now - widget.session.startUtc;
        final elapsedMin = (elapsedMs / msPerMinute).floor();
        final remainingMs = isStopwatch ? 0 : target - now;
        final finished = !isStopwatch && remainingMs <= 0;
        if (finished && !_completionNotified) {
          _completionNotified = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showCompletionSuggestion(context, elapsedMin);
          });
        }
        final elapsed = _formatElapsed(elapsedMs);
        final remaining = finished
            ? '00:00'
            : '${(remainingMs ~/ msPerMinute).toString().padLeft(2, '0')}:${((remainingMs % msPerMinute) ~/ 1000).toString().padLeft(2, '0')}';
        final display = isStopwatch ? elapsed : remaining;
        final isBreak = widget.session.phase == 'break';
        final nextLabel = isBreak ? 'Start focus' : 'Start break';
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBreak
                              ? 'Break over - $elapsedMin min elapsed.'
                              : 'Focus complete - $elapsedMin min elapsed.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () =>
                              _completeAndStartNext(context, ref, elapsedMin),
                          child: Text('Complete and $nextLabel'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Center(
                child: Semantics(
                  label: isStopwatch
                      ? 'Focus elapsed time: $display'
                      : 'Focus time remaining: $display',
                  child: Text(
                    display,
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
              if (finished) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _completeAndStartNext(context, ref, elapsedMin),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(nextLabel),
                ),
              ],
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

  Future<void> _showCompletionSuggestion(
    BuildContext context,
    int elapsedMin,
  ) async {
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final isBreak = widget.session.phase == 'break';
    final nextLabel = isBreak ? 'start a focus session' : 'start a break';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBreak ? 'Break over' : 'Focus session complete'),
        content: Text(
          '${isBreak ? 'Break' : 'Focus'} time is up. Would you like to $nextLabel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _completeAndStartNext(context, ref, elapsedMin);
            },
            child: Text(isBreak ? 'Start focus' : 'Start break'),
          ),
        ],
      ),
    );
  }

  bool _isAbandoned(int now) => now - widget.session.startUtc > 12 * msPerHour;

  Future<int?> _completeSession(WidgetRef ref) async {
    final repo = ref.read(focusRepositoryProvider);
    final note = await _askNote(context);
    if (!mounted) return null;
    final kept = await repo.finishSession(widget.session.id, note: note);
    await AlarmScheduler.cancel(_requestCode(widget.session.id));
    await SystemLauncher.stopFocusChronometer();
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      if (settings.focusDnd) await SystemLauncher.setDnd(false);
    } catch (_) {}
    final habitId = widget.session.habitId;
    if (habitId != null && kept > 0 && mounted) {
      await _creditHabit(context, ref, habitId, kept);
    }
    return kept;
  }

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    int elapsedMin,
  ) async {
    await _completeSession(ref);
    _refresh(ref);
  }

  Future<void> _completeAndStartNext(
    BuildContext context,
    WidgetRef ref,
    int elapsedMin,
  ) async {
    final startBreak = widget.session.phase != 'break';
    await _completeAndStartPhase(
      context,
      ref,
      elapsedMin,
      startBreak: startBreak,
    );
  }

  Future<void> _completeAndStartPhase(
    BuildContext context,
    WidgetRef ref,
    int elapsedMin, {
    required bool startBreak,
  }) async {
    final kept = await _completeSession(ref);
    if (kept == null || !mounted) return;
    await _startNextSession(ref, startBreak: startBreak);
  }

  Future<void> _startNextSession(
    WidgetRef ref, {
    required bool startBreak,
  }) async {
    var durationMin = startBreak ? 5 : 25;
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      durationMin = startBreak
          ? settings.focusBreakMin
          : settings.focusSetupMin;
    } catch (_) {}
    final phase = startBreak ? 'break' : 'focus';
    final preset = AlarmPreset.notification;
    if (mounted) {
      await AppPermissions.ensureAlarmPrereqs(
        context,
        exactAlarm: preset.needsAlarmClock,
        fullScreen: preset.usesFullScreen,
      );
    }
    if (!mounted) return;
    final repo = ref.read(focusRepositoryProvider);
    final id = await repo.startSession(
      taskId: widget.session.taskId,
      habitId: widget.session.habitId,
      durationMin: durationMin,
      phase: phase,
      alarmPreset: preset.id,
    );
    final session = await repo.currentSession();
    if (session != null && session.id == id) {
      await _scheduleEndAlarm(session);
      await SystemLauncher.startFocusChronometer(
        '$phase session',
        session.startUtc,
      );
      try {
        final settings = await ref.read(settingsRepositoryProvider.future);
        if (settings.focusDnd) await SystemLauncher.setDnd(true);
      } catch (_) {}
    }
    _refresh(ref);
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingOperationsProvider);
    final opId = await pending.scheduleFocusDelete(widget.session.id);
    await AlarmScheduler.cancel(_requestCode(widget.session.id));
    await SystemLauncher.stopFocusChronometer();
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      if (settings.focusDnd) await SystemLauncher.setDnd(false);
    } catch (_) {}
    _refresh(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Session discarded.'),
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
