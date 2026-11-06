// Resolves initial date/time picker values: current field > remembered > fallback.
// Pure functions (no Flutter/SharedPreferences) so they stay testable.

class PickerMemoryKeys {
  static const taskPlannedDate = 'task.plannedDate';
  static const taskDueDate = 'task.dueDate';
  static const taskPlannedStart = 'task.plannedStart';
  static const taskPlannedEnd = 'task.plannedEnd';
  static const taskDueTime = 'task.dueTime';
  static const eventStart = 'event.start';
  static const eventEnd = 'event.end';
  static const eventRruleUntil = 'event.rruleUntil';
  static const habitStartDate = 'habit.startDate';
  static const habitReminderTime = 'habit.reminderTime';
  static const countdownTargetDate = 'countdown.targetDate';
  static const countdownAlertTime = 'countdown.alertTime';
  static const smartListDueFrom = 'smartList.dueFrom';
  static const smartListDueTo = 'smartList.dueTo';
}

DateTime resolvePickerDate({
  String? current,
  String? remembered,
  required DateTime fallback,
}) {
  final cur = current == null ? null : DateTime.tryParse(current);
  if (cur != null) return DateTime(cur.year, cur.month, cur.day);
  final rem = remembered == null ? null : DateTime.tryParse(remembered);
  if (rem != null) return DateTime(rem.year, rem.month, rem.day);
  return DateTime(fallback.year, fallback.month, fallback.day);
}

int resolvePickerTimeMinutes({
  int? currentMinutes,
  String? rememberedHhmm,
  required int fallbackMinutes,
}) {
  if (currentMinutes != null) return currentMinutes;
  final rem = parseHhmm(rememberedHhmm);
  if (rem != null) return rem;
  return fallbackMinutes;
}

DateTime resolvePickerDateTime({
  String? currentIso,
  String? rememberedIso,
  required DateTime fallback,
}) {
  final cur = currentIso == null ? null : DateTime.tryParse(currentIso);
  if (cur != null) return cur;
  final rem = rememberedIso == null ? null : DateTime.tryParse(rememberedIso);
  if (rem != null) return rem;
  return fallback;
}

int? parseHhmm(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

String formatHhmm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
