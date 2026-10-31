// Reminder offsets: early/at-time plain notifications.
// Alarms (AlarmPreset) fire at the item time with a stronger style and
// never replace these reminders. Pure Dart, no Flutter imports.
import 'dart:convert';

class ReminderOptions {
  static const atTime = 0;
  static const m5 = 5;
  static const m10 = 10;
  static const m15 = 15;
  static const m30 = 30;
  static const h1 = 60;
  static const d1 = 1440;
  static const d2 = 2880;
  static const w1 = 10080;

  static const defaultsTimed = [m10];
  static const defaultsAllDay = [d1];

  static const presets = [atTime, m5, m10, m15, m30, h1, d1, d2, w1];

  static String label(int minutes) {
    return switch (minutes) {
      0 => 'At time',
      1 => '1 minute before',
      < 60 => '$minutes minutes before',
      60 => '1 hour before',
      < 1440 => '${minutes ~/ 60} hours before',
      1440 => '1 day before',
      2880 => '2 days before',
      10080 => '1 week before',
      _ when minutes % 1440 == 0 => '${minutes ~/ 1440} days before',
      _ => '$minutes minutes before',
    };
  }
}

/// Parses the events.reminders JSON column to a sorted offset list.
/// Accepts "[10,60]", "10,60", "10" or null. Unknown entries dropped.
List<int> parseReminderOffsets(String? raw, {bool allDay = false}) {
  if (raw == null || raw.trim().isEmpty) {
    return allDay
        ? ReminderOptions.defaultsAllDay
        : ReminderOptions.defaultsTimed;
  }
  try {
    final t = raw.trim();
    List<dynamic> list;
    if (t.startsWith('[')) {
      list = jsonDecode(t) as List<dynamic>;
    } else {
      list = t.split(',');
    }
    final out = <int>{};
    for (final e in list) {
      final v = e is int ? e : int.tryParse('$e'.trim());
      if (v != null && v >= 0 && v <= 40320) out.add(v);
    }
    if (out.isEmpty) {
      return allDay
          ? ReminderOptions.defaultsAllDay
          : ReminderOptions.defaultsTimed;
    }
    final sorted = out.toList()..sort();
    return sorted;
  } catch (_) {
    return allDay
        ? ReminderOptions.defaultsAllDay
        : ReminderOptions.defaultsTimed;
  }
}

String encodeReminderOffsets(List<int> offsets) {
  final sorted = {...offsets}.toList()..sort();
  return jsonEncode(sorted);
}
