import '../domain/focus_mode.dart';

class FocusTimerState {
  const FocusTimerState({
    this.isRunning = false,
    this.mode = FocusMode.stopwatch,
    this.pomodoroPhase = PomodoroPhase.work,
    this.elapsed = Duration.zero,
    this.linkedTaskId,
    this.linkedHabitId,
    this.note = '',
    this.keepScreenOn = false,
    this.startedAt,
  });

  final bool isRunning;
  final FocusMode mode;
  final PomodoroPhase pomodoroPhase;
  final Duration elapsed;
  final String? linkedTaskId;
  final String? linkedHabitId;
  final String note;
  final bool keepScreenOn;

  /// Wall-clock start of the current run — null when idle. Kept here
  /// (rather than only ever computing elapsed from a Timer tick count)
  /// so the ongoing notification's `usesChronometer` field has a stable
  /// reference point that survives this state being rebuilt.
  final DateTime? startedAt;

  Duration get pomodoroTarget =>
      pomodoroPhase == PomodoroPhase.work ? PomodoroDefaults.workDuration : PomodoroDefaults.breakDuration;

  FocusTimerState copyWith({
    bool? isRunning,
    FocusMode? mode,
    PomodoroPhase? pomodoroPhase,
    Duration? elapsed,
    String? Function()? linkedTaskId,
    String? Function()? linkedHabitId,
    String? note,
    bool? keepScreenOn,
    DateTime? Function()? startedAt,
  }) {
    return FocusTimerState(
      isRunning: isRunning ?? this.isRunning,
      mode: mode ?? this.mode,
      pomodoroPhase: pomodoroPhase ?? this.pomodoroPhase,
      elapsed: elapsed ?? this.elapsed,
      linkedTaskId: linkedTaskId != null ? linkedTaskId() : this.linkedTaskId,
      linkedHabitId: linkedHabitId != null ? linkedHabitId() : this.linkedHabitId,
      note: note ?? this.note,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      startedAt: startedAt != null ? startedAt() : this.startedAt,
    );
  }
}
