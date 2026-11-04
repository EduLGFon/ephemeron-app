// Eisenhower matrix classification. Pure Dart.

enum EisenhowerQuadrant { doFirst, schedule, delegate, eliminate, unclassified }

/// Board grouping mode: urgency/importance classification or stored priority.
enum MatrixMode { auto, priority }

MatrixMode matrixModeFromName(String? name) => MatrixMode.values.firstWhere(
  (mode) => mode.name == name,
  orElse: () => MatrixMode.auto,
);

/// Stored priority (1-4) as the user-facing P label. 0 (none) has no label.
String? matrixPriorityLabel(int priority) => switch (priority) {
  4 => 'P1',
  3 => 'P2',
  2 => 'P3',
  1 => 'P4',
  _ => null,
};

EisenhowerQuadrant classifyTask({
  required int priority, // 0 none, 1 low, 2 medium, 3 high
  DateTime? dueDate,
  required DateTime now,
  int urgentDays = 2,
}) {
  final important = priority >= 2;
  bool urgent = false;
  if (dueDate != null) {
    final diff = dueDate.difference(now).inDays;
    urgent = diff <= urgentDays; // overdue counts as urgent
  }
  if (priority == 0 && dueDate == null) return EisenhowerQuadrant.unclassified;
  if (important && urgent) return EisenhowerQuadrant.doFirst;
  if (important && !urgent) return EisenhowerQuadrant.schedule;
  if (!important && urgent) return EisenhowerQuadrant.delegate;
  return EisenhowerQuadrant.eliminate;
}
