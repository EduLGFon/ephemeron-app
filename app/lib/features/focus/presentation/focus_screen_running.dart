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
        final isStopwatch = target == null;
        final elapsedMs = now - widget.session.startUtc;
        final elapsedMin = (elapsedMs / msPerMinute).floor();
        final remainingMs = isStopwatch ? 0 : target - now;
        final finished = !isStopwatch && remainingMs <= 0;
        final elapsed = _formatElapsed(elapsedMs);
        final remaining = finished
            ? '00:00'
            : '${(remainingMs ~/ msPerMinute).toString().padLeft(2, '0')}:${((remainingMs % msPerMinute) ~/ 1000).toString().padLeft(2, '0')}';
        final display = isStopwatch ? elapsed : remaining;
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

  bool _isAbandoned(int now) => now - widget.session.startUtc > 12 * msPerHour;

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
