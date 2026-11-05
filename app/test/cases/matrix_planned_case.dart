import 'package:ephemeron/domain/tasks/eisenhower.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planned date does not affect urgency classification', () {
    final now = DateTime(2026, 1, 1);
    final dueLater = now.add(const Duration(days: 30));

    // Medium importance (priority 2) with a near planned date but a far due
    // date stays in Schedule because urgency uses the due date only.
    expect(
      classifyTask(priority: 2, dueDate: dueLater, now: now),
      EisenhowerQuadrant.schedule,
    );

    // Low importance (priority 1) with the same dates is Eliminate.
    expect(
      classifyTask(priority: 1, dueDate: dueLater, now: now),
      EisenhowerQuadrant.eliminate,
    );
  });
}
