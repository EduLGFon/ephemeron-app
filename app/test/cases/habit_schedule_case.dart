import 'package:ephemeron/domain/habits/streaks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily habits are scheduled every day', () {
    final spec = HabitSpec(frequency: 'daily');
    expect(isHabitScheduled(spec, DateTime(2026, 3, 9)), isTrue);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 10)), isTrue);
  });

  test('weekday habits follow the mask', () {
    // Monday-Friday only.
    final spec = HabitSpec(frequency: 'weekdays', weekdaysMask: 31);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 6)), isTrue); // Friday
    expect(isHabitScheduled(spec, DateTime(2026, 3, 7)), isFalse); // Saturday
    expect(isHabitScheduled(spec, DateTime(2026, 3, 8)), isFalse); // Sunday
    expect(isHabitScheduled(spec, DateTime(2026, 3, 9)), isTrue); // Monday
  });

  test('interval habits anchor on the start date', () {
    final spec = HabitSpec(
      frequency: 'interval',
      intervalDays: 3,
      startDate: '2026-03-02',
    );
    expect(isHabitScheduled(spec, DateTime(2026, 3, 2)), isTrue);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 3)), isFalse);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 5)), isTrue);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 8)), isTrue);
  });

  test('days before the start date are excluded', () {
    final spec = HabitSpec(frequency: 'daily', startDate: '2026-03-10');
    expect(isHabitScheduled(spec, DateTime(2026, 3, 9)), isFalse);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 10)), isTrue);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 11)), isTrue);
  });

  test('weekly-target habits are available every day', () {
    final spec = HabitSpec(frequency: 'weekly', weeklyTarget: 3);
    for (var day = 2; day <= 8; day++) {
      expect(isHabitScheduled(spec, DateTime(2026, 3, day)), isTrue);
    }
  });

  test('weekly habits still respect a future start date', () {
    final spec = HabitSpec(
      frequency: 'weekly',
      weeklyTarget: 2,
      startDate: '2026-03-10',
    );
    expect(isHabitScheduled(spec, DateTime(2026, 3, 9)), isFalse);
    expect(isHabitScheduled(spec, DateTime(2026, 3, 10)), isTrue);
  });
}
