import 'package:ephemeron/domain/alarms/alarm_preset.dart';
import 'package:ephemeron/domain/alarms/alarm_window.dart';
import 'package:ephemeron/domain/alarms/reminder.dart';
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
          preset: h.isEven ? 'notification' : 'full_short',
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
        preset: 'notification',
      ),
    ], nowUtcMs: now);
    expect(planned, isEmpty);
  });

  test('preset clock requirements', () {
    expect(needsAlarmClock('notification'), isFalse);
    expect(needsAlarmClock('full_short'), isTrue);
    expect(needsAlarmClock('full_long'), isTrue);
    // Legacy mapping stays compatible.
    expect(needsAlarmClock('light'), isFalse);
    expect(needsAlarmClock('medium'), isTrue);
    expect(needsAlarmClock('constant'), isTrue);
  });

  test('three presets parse and describe', () {
    expect(parseAlarmPreset(null), isNull);
    expect(parseAlarmPreset('none'), isNull);
    expect(parseAlarmPreset('notification'), AlarmPreset.notification);
    expect(parseAlarmPreset('full_short'), AlarmPreset.fullScreenShort);
    expect(parseAlarmPreset('full_long'), AlarmPreset.fullScreenLong);
    expect(parseAlarmPreset('light'), AlarmPreset.notification);
    expect(parseAlarmPreset('constant'), AlarmPreset.fullScreenLong);
    expect(AlarmPreset.fullScreenLong.usesFullScreen, isTrue);
    expect(AlarmPreset.notification.usesFullScreen, isFalse);
    expect(AlarmPreset.fullScreenLong.maxRepeats, 30);
  });

  test('reminder offsets parse and label', () {
    expect(parseReminderOffsets(null), [10]);
    expect(parseReminderOffsets(null, allDay: true), [1440]);
    expect(parseReminderOffsets('[5,10]'), [5, 10]);
    expect(encodeReminderOffsets([10, 5]), '[5,10]');
    expect(ReminderOptions.label(0), 'At time');
    expect(ReminderOptions.label(1440), '1 day before');
  });
}
