import 'dart:convert';

/// MVP recurrence scope: daily, weekly on specific weekdays, or yearly
/// (for the common "every year on this date" case). This is
/// deliberately simpler than a full RRULE — matches the "basic repeat"
/// line item from the MVP cut, not the full custom-recurrence feature.
enum RecurrenceType { none, daily, weekly, yearly }

class TaskRecurrence {
  const TaskRecurrence({required this.type, this.weekdays = const []});

  static const none = TaskRecurrence(type: RecurrenceType.none);

  final RecurrenceType type;

  /// ISO-8601 weekday numbers (1 = Monday ... 7 = Sunday). Only
  /// meaningful when [type] is [RecurrenceType.weekly]; an empty list
  /// there means "every 7 days from the original due date" rather than
  /// specific days.
  final List<int> weekdays;

  bool get isRecurring => type != RecurrenceType.none;

  String encode() => jsonEncode({
        'type': type.name,
        'weekdays': weekdays,
      });

  static TaskRecurrence decode(String? raw) {
    if (raw == null || raw.isEmpty) return none;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TaskRecurrence(
        type: RecurrenceType.values.byName(map['type'] as String),
        weekdays: (map['weekdays'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
      );
    } catch (_) {
      return none;
    }
  }

  /// The next due date after [currentDue], or null if not recurring.
  /// Preserves time-of-day from [currentDue] in every case.
  DateTime? nextOccurrence(DateTime currentDue) {
    switch (type) {
      case RecurrenceType.none:
        return null;
      case RecurrenceType.daily:
        return currentDue.add(const Duration(days: 1));
      case RecurrenceType.yearly:
        return DateTime(
          currentDue.year + 1,
          currentDue.month,
          currentDue.day,
          currentDue.hour,
          currentDue.minute,
        );
      case RecurrenceType.weekly:
        if (weekdays.isEmpty) {
          return currentDue.add(const Duration(days: 7));
        }
        final sorted = [...weekdays]..sort();
        for (var offset = 1; offset <= 7; offset++) {
          final candidate = currentDue.add(Duration(days: offset));
          if (sorted.contains(candidate.weekday)) return candidate;
        }
        // Unreachable in practice (every weekday list of length >=1
        // matches within 7 days), but keeps the function total.
        return currentDue.add(const Duration(days: 7));
    }
  }
}
