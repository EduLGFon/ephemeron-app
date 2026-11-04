// Pure helpers for habit stopwatch timers (no Flutter/Riverpod dependencies).
bool isMinuteUnit(String? unit) {
  if (unit == null) return false;
  final u = unit.trim().toLowerCase();
  return u == 'min' || u == 'mins' || u == 'minute' || u == 'minutes';
}

Duration timerElapsed({required int startedAtMs, required int nowMs}) {
  final ms = nowMs - startedAtMs;
  if (ms < 0) return Duration.zero;
  return Duration(milliseconds: ms);
}

double elapsedMinutes(Duration elapsed) => elapsed.inSeconds / 60.0;

String formatElapsed(Duration elapsed) {
  final totalSeconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final hh = hours.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
  return '$mm:$ss';
}
