import 'package:ephemeron/domain/habits/habit_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fractional minute progress shows percentage of goal', () {
    expect(
      formatHabitProgress(unit: 'min', amount: 12.5, goal: 30),
      '42% of 30 min',
    );
  });

  test('whole minute progress keeps exact amount', () {
    expect(formatHabitProgress(unit: 'min', amount: 10, goal: 30), '10/30 min');
  });

  test('exact tooltip formats minutes and seconds', () {
    expect(
      formatHabitExact(unit: 'min', amount: 12.5, goal: 30),
      '12m 30s / 30 min',
    );
    expect(
      formatHabitExact(unit: 'min', amount: 61 / 60, goal: 30),
      '1m 1s / 30 min',
    );
  });

  test('non-minute units are unchanged', () {
    expect(
      formatHabitProgress(unit: 'count', amount: 12.333333, goal: 30),
      '12.333333/30 count',
    );
  });
}
