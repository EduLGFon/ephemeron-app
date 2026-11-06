// Part of the habits screen library: start/stop control for minute-based
// habits that feeds the elapsed time back into the daily log.
part of '../habits_screen.dart';

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
