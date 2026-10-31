import 'package:ephemeron/domain/alarms/alarm_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps horizon plus next N future alarms ordered', () {
    final now = DateTime.utc(2026, 3, 2, 12).millisecondsSinceEpoch;
    final cands = [
      for (var h = 1; h <= 200; h++)
        AlarmCandidate(
          sourceType: 'event',
          sourceId: 'e$h',
          fireAtUtcMs: now + h * 3600000,
          preset: h.isEven ? 'light' : 'strong',
        ),
    ];
    final planned = planAlarmWindow(
      cands,
      nowUtcMs: now,
      horizonHours: 48,
      maxFuture: 60,
    );
    expect(planned.length, 48 + 60);
    for (var i = 1; i < planned.length; i++) {
      expect(
        planned[i].fireAtUtcMs,
        greaterThanOrEqualTo(planned[i - 1].fireAtUtcMs),
      );
    }
    expect(
      planned.map((p) => p.requestCode).toSet(),
      hasLength(planned.length),
    );
  });

  test('drops past alarms', () {
    final now = DateTime.utc(2026, 3, 2, 12).millisecondsSinceEpoch;
    final planned = planAlarmWindow([
      AlarmCandidate(
        sourceType: 'task',
        sourceId: 't1',
        fireAtUtcMs: now - 1000,
        preset: 'light',
      ),
    ], nowUtcMs: now);
    expect(planned, isEmpty);
  });

  test('preset clock requirements', () {
    expect(needsAlarmClock('light'), isFalse);
    expect(needsAlarmClock('medium'), isTrue);
    expect(needsAlarmClock('strong'), isTrue);
    expect(needsAlarmClock('constant'), isTrue);
  });
}
