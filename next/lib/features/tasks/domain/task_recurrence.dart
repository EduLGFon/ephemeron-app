import 'dart:convert';
import 'package:meta/meta.dart';

enum RecurrenceType { none, daily, weekly, yearly }

@immutable
class TaskRecurrence {
  const TaskRecurrence({required this.type, this.weekdays = const []});

  static const none = TaskRecurrence(type: RecurrenceType.none);

  final RecurrenceType type;
  final List<int> weekdays;

  bool get isRecurring => type != RecurrenceType.none;

  String encode() => jsonEncode({
        'type': type.name,
        'weekdays': weekdays,
      });

  static TaskRecurrence decode(String? raw) {
    if (raw == null || raw.isEmpty) return TaskRecurrence.none;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TaskRecurrence(
        type: RecurrenceType.values.byName(map['type'] as String),
        weekdays: (map['weekdays'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
      );
    } catch (_) {
      return TaskRecurrence.none;
    }
  }

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
        return currentDue.add(const Duration(days: 7));
    }
  }
}