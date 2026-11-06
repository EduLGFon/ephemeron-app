part of 'focus_screen.dart';

extension _RunningViewActions on _RunningViewState {
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
