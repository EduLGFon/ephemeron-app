import 'package:flutter_test/flutter_test.dart';
import 'package:ephemeron/features/calendar/presentation/event_form_sheet.dart';

void main() {
  group('RecurrenceConfig RRULE conversion', () {
    test('Daily recurrence to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.daily,
        interval: 2,
        duration: RepeatDuration.forever,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13));
      expect(rrule, ['RRULE:FREQ=DAILY;INTERVAL=2']);
    });

    test('Daily recurrence with COUNT to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.daily,
        interval: 1,
        duration: RepeatDuration.specificTimes,
        repeatTimes: 5,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13));
      expect(rrule, ['RRULE:FREQ=DAILY;COUNT=5']);
    });

    test('Daily recurrence with UNTIL to RRULE', () {
      final untilDate = DateTime(2026, 8, 13, 0, 0, 0);
      final config = RecurrenceConfig(
        type: RecurrenceType.daily,
        interval: 1,
        duration: RepeatDuration.until,
        untilDate: untilDate,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13));
      // check that it starts with the RRULE prefix and contains UNTIL with the correct year/month/day
      expect(rrule.first, startsWith('RRULE:FREQ=DAILY;UNTIL=20260813'));
    });

    test('Weekly recurrence to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.weekly,
        interval: 3,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13));
      expect(rrule, ['RRULE:FREQ=WEEKLY;INTERVAL=3']);
    });

    test('Monthly recurrence on dayOfMonth to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.monthly,
        interval: 1,
        monthlyMode: MonthlyRepeatMode.dayOfMonth,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13)); // 13th
      expect(rrule, ['RRULE:FREQ=MONTHLY;BYMONTHDAY=13']);
    });

    test('Monthly recurrence on dayOfWeek to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.monthly,
        interval: 1,
        monthlyMode: MonthlyRepeatMode.dayOfWeek,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13)); // 13th July 2026 is Monday, and 2nd Monday (7 + 6)
      // 13th is the second Monday since 13 = 1 * 7 + 6, so ((13-1) ~/ 7) + 1 = 2nd
      expect(rrule, ['RRULE:FREQ=MONTHLY;BYDAY=2MO']);
    });

    test('Yearly recurrence to RRULE', () {
      const config = RecurrenceConfig(
        type: RecurrenceType.yearly,
      );
      final rrule = config.toRruleList(DateTime(2026, 7, 13));
      expect(rrule, ['RRULE:FREQ=YEARLY']);
    });

    test('Parse from RRULE: daily', () {
      final config = RecurrenceConfig.fromRruleList(['RRULE:FREQ=DAILY;INTERVAL=2']);
      expect(config.type, RecurrenceType.daily);
      expect(config.interval, 2);
      expect(config.duration, RepeatDuration.forever);
    });

    test('Parse from RRULE: monthly day of week', () {
      final config = RecurrenceConfig.fromRruleList(['RRULE:FREQ=MONTHLY;BYDAY=2MO']);
      expect(config.type, RecurrenceType.monthly);
      expect(config.monthlyMode, MonthlyRepeatMode.dayOfWeek);
    });

    test('Parse from RRULE: with COUNT', () {
      final config = RecurrenceConfig.fromRruleList(['RRULE:FREQ=DAILY;COUNT=15']);
      expect(config.type, RecurrenceType.daily);
      expect(config.duration, RepeatDuration.specificTimes);
      expect(config.repeatTimes, 15);
    });

    test('Parse from RRULE: with UNTIL', () {
      final config = RecurrenceConfig.fromRruleList(['RRULE:FREQ=DAILY;UNTIL=20260813T000000Z']);
      expect(config.type, RecurrenceType.daily);
      expect(config.duration, RepeatDuration.until);
      expect(config.untilDate, DateTime(2026, 8, 13));
    });
  });
}
