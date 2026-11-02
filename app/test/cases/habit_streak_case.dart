import 'package:ephemeron/domain/countdowns/countdown.dart';
import 'package:ephemeron/domain/habits/streaks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily streak counts consecutive done days', () {
    final spec = HabitSpec(frequency: 'daily');
    final done = {'2026-03-08', '2026-03-09', '2026-03-10'};
    expect(currentStreak(spec, '2026-03-10', done.contains, (_) => false), 3);
  });
  test('missed scheduled day breaks streak', () {
    final spec = HabitSpec(frequency: 'daily');
    final done = {'2026-03-08', '2026-03-10'};
    expect(currentStreak(spec, '2026-03-10', done.contains, (_) => false), 1);
  });
  test('skipped day is neutral', () {
    final spec = HabitSpec(frequency: 'daily');
    final done = {'2026-03-08', '2026-03-10'};
    bool skip(String d) => d == '2026-03-09';
    expect(currentStreak(spec, '2026-03-10', done.contains, skip), 2);
  });
  test('weekdays mask ignores off days', () {
    final spec = HabitSpec(frequency: 'weekdays', weekdaysMask: 31);
    final done = {'2026-03-06', '2026-03-09'};
    expect(currentStreak(spec, '2026-03-09', done.contains, (_) => false), 2);
  });
  test('weekly target counts completed weeks', () {
    final spec = HabitSpec(frequency: 'weekly', weeklyTarget: 2);
    bool isDone(String d) =>
        d == '2026-03-02' || d == '2026-03-04' || d == '2026-03-09';
    expect(currentStreak(spec, '2026-03-10', isDone, (_) => false), 1);
  });
  test('best streak recorded', () {
    final spec = HabitSpec(frequency: 'daily');
    final done = {'2026-03-01', '2026-03-02', '2026-03-03', '2026-03-10'};
    expect(bestStreak(spec, '2026-03-10', done.contains, (_) => false), 3);
    expect(currentStreak(spec, '2026-03-10', done.contains, (_) => false), 1);
  });
  test('countdown next date and leap day', () {
    final n = countdownNextDate(
      month: 3,
      day: 15,
      today: DateTime(2026, 3, 10),
      yearlyRepeat: true,
    );
    expect(n, DateTime(2026, 3, 15));
    expect(daysUntil(n, DateTime(2026, 3, 10)), 5);
    final past = countdownNextDate(
      month: 1,
      day: 5,
      today: DateTime(2026, 3, 10),
      yearlyRepeat: true,
    );
    expect(past, DateTime(2027, 1, 5));
    final leap = countdownNextDate(
      month: 2,
      day: 29,
      today: DateTime(2026, 1, 1),
      yearlyRepeat: true,
    );
    expect(leap, DateTime(2026, 2, 28));
    final once = countdownNextDate(
      month: 1,
      day: 5,
      today: DateTime(2026, 3, 10),
      yearlyRepeat: false,
    );
    expect(once, DateTime(2026, 1, 5));
    expect(daysUntil(once, DateTime(2026, 3, 10)) < 0, isTrue);
  });
}
