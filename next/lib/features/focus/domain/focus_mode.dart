enum FocusMode { pomodoro, stopwatch }

/// Fixed for MVP — customizable work/break lengths are Phase 2.
abstract final class PomodoroDefaults {
  static const workDuration = Duration(minutes: 25);
  static const breakDuration = Duration(minutes: 5);
}

enum PomodoroPhase { work, breakTime }
