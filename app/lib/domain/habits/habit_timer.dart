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

String _fmtNumber(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

String formatHabitProgress({
  required String? unit,
  required double amount,
  required double goal,
}) {
  final u = unit ?? '';
  if (isMinuteUnit(unit) && amount != amount.roundToDouble()) {
    var pct = goal > 0 ? (amount / goal * 100).round() : 0;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    return '$pct% of ${_fmtNumber(goal)} $u'.trim();
  }
  return '${_fmtNumber(amount)}/${_fmtNumber(goal)} $u'.trim();
}

String formatHabitExact({
  required String? unit,
  required double amount,
  required double goal,
}) {
  final u = unit ?? '';
  if (isMinuteUnit(unit)) {
    final totalSeconds = (amount * 60).round();
    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    String amountLabel;
    if (mins == 0) {
      amountLabel = '${secs}s';
    } else if (secs == 0) {
      amountLabel = '$mins min';
    } else {
      amountLabel = '${mins}m ${secs}s';
    }
    return '$amountLabel / ${_fmtNumber(goal)} $u'.trim();
  }
  return '${_fmtNumber(amount)}/${_fmtNumber(goal)} $u'.trim();
}
