import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:ephemeron/domain/recurrence/recurrence_rule.dart';

DateTime utc(int y, int m, int d, [int h = 9, int min = 0]) =>
    DateTime.utc(y, m, d, h, min);

void main() {
  setUpAll(() => tzdata.initializeTimeZones());

  test('daily keeps wall clock across DST', () {
    final start = utc(2026, 3, 7, 14);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY;COUNT=4',
      tzId: 'America/New_York',
    );
    expect(out.length, 4);
    for (final o in out) {
      final t = tz.TZDateTime.from(o, tz.getLocation('America/New_York'));
      expect(t.hour, 9);
      expect(t.minute, 0);
    }
  });

  test('monthly 31st skips short months', () {
    final start = utc(2026, 1, 31, 10);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=MONTHLY;COUNT=5',
    );
    expect(out.length, 5);
    expect(out[0].month, 1);
    expect(out[1].month, 3);
    expect(out[2].month, 5);
  });

  test('leap day yearly defaults to Feb 28 on non-leap years', () {
    final start = utc(2024, 2, 29, 8);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=YEARLY;COUNT=3',
    );
    expect(out.length, 3);
    expect(out[0].month, 2);
    expect(out[0].day, 29);
    expect(out[1].month, 2);
    expect(out[1].day, 28);
    expect(out[2].month, 2);
    expect(out[2].day, 28);
  });

  test('UNTIL date form for all-day', () {
    final start = utc(2026, 1, 1);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY;UNTIL=20260105',
      allDay: true,
    );
    expect(out.length, 5);
    expect(out.last.day, 5);
  });

  test('UNTIL UTC Z for timed', () {
    final start = utc(2026, 1, 1, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY;UNTIL=20260103T090000Z',
    );
    expect(out.length, 3);
  });

  test('EXDATE removes occurrence', () {
    final start = utc(2026, 1, 1, 9);
    final ex = utc(2026, 1, 2, 9).millisecondsSinceEpoch;
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY;COUNT=4',
      exdateUtcMs: {ex},
    );
    expect(out.length, 3);
    expect(out.any((d) => d.day == 2), false);
  });

  test('RDATE adds occurrence', () {
    final start = utc(2026, 1, 1, 9);
    final rd = utc(2026, 1, 10, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY;COUNT=3',
      rdatesUtc: [rd],
    );
    expect(out.length, 4);
  });

  test('cap at 1000 for infinite series', () {
    final start = utc(2026, 1, 1, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=DAILY',
      cap: 1000,
    );
    expect(out.length, 1000);
  });

  test('BYDAY ordinals monthly: 2nd Monday', () {
    final start = utc(2026, 1, 1, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=MONTHLY;BYDAY=2MO;COUNT=3',
    );
    for (final o in out) {
      expect(o.weekday, DateTime.monday);
    }
    expect(out[0].day, 12);
  });

  test('BYMONTHDAY -1 last day', () {
    final start = utc(2026, 1, 31, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=3',
    );
    expect(out[0].day, 31);
    expect(out[1].day, 28);
    expect(out[2].day, 31);
  });

  test('weekly interval with WKST', () {
    final start = utc(2026, 1, 5, 9);
    final out = expandOccurrences(
      startUtc: start,
      rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO;COUNT=3;WKST=MO',
    );
    expect(out.length, 3);
    expect(out[1].difference(out[0]).inDays, 14);
  });
}
