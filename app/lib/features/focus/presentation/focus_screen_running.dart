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
  bool _handlingPendingNext = false;

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

  bool _isAbandoned(int now) => now - widget.session.startUtc > 12 * msPerHour;
}
