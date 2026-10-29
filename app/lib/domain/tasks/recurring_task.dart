// Recurring task helpers. Pure Dart; uses recurrence engine for date math.

import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';

/// Compute the next due date for a recurring task after completion.
///
/// [mode] is 'from_due_date' (default) or 'from_completion_date'.
DateTime? nextTaskDueDate({
  required DateTime? currentDueUtc,
  required DateTime completedAtUtc,
  required String? rrule,
  required String mode,
  String? tzId,
}) {
  if (rrule == null || rrule.isEmpty) return null;
  final base = (mode == 'from_completion_date')
      ? completedAtUtc
      : (currentDueUtc ?? completedAtUtc);
  final occs = expandOccurrences(
    startUtc: base,
    rrule: rrule,
    tzId: tzId,
    allDay: currentDueUtc == null ? false : (currentDueUtc.hour == 0 && currentDueUtc.minute == 0 && currentDueUtc.second == 0),
    rangeStartUtc: base.add(const Duration(seconds: 1)),
    cap: 1,
  );
  if (occs.isEmpty) return null;
  return occs.first;
}
