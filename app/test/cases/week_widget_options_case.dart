import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/services/week_calendar_data.dart';
import 'package:ephemeron/data/services/week_calendar_image.dart';
import 'package:ephemeron/data/services/week_widget_options.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('theme parsing defaults to light', () {
    expect(WeekWidgetTheme.parse(null), WeekWidgetTheme.light);
    expect(WeekWidgetTheme.parse('nope'), WeekWidgetTheme.light);
    expect(WeekWidgetTheme.parse('dark'), WeekWidgetTheme.dark);
    expect(WeekWidgetTheme.parse('transparent'), WeekWidgetTheme.transparent);
  });

  test('day count sanitizes to offered values', () {
    expect(WeekWidgetOptions.sanitizeDayCount(1), 1);
    expect(WeekWidgetOptions.sanitizeDayCount(3), 3);
    expect(WeekWidgetOptions.sanitizeDayCount(5), 5);
    expect(WeekWidgetOptions.sanitizeDayCount(7), 7);
    expect(WeekWidgetOptions.sanitizeDayCount(4), 7);
    expect(WeekWidgetOptions.sanitizeDayCount(0), 7);
  });

  test('day key round-trips and rejects bad input', () {
    final day = DateTime(2026, 11, 4);
    expect(WeekWidgetOptions.dayKey(day), '2026-11-04');
    expect(
      WeekWidgetOptions.tryParseDayKey('2026-11-04'),
      DateTime(2026, 11, 4),
    );
    expect(WeekWidgetOptions.tryParseDayKey('today'), isNull);
    expect(WeekWidgetOptions.tryParseDayKey('2026-13-01'), isNull);
    expect(WeekWidgetOptions.tryParseDayKey('2026-02-30'), isNull);
    expect(WeekWidgetOptions.tryParseDayKey(''), isNull);
  });

  test('anchor shifts by the visible span', () {
    final anchor = DateTime(2026, 11, 2);
    expect(WeekWidgetOptions.shiftAnchor(anchor, 7, 1), DateTime(2026, 11, 9));
    expect(
      WeekWidgetOptions.shiftAnchor(anchor, 7, -1),
      DateTime(2026, 10, 26),
    );
    expect(WeekWidgetOptions.shiftAnchor(anchor, 3, 1), DateTime(2026, 11, 5));
    expect(WeekWidgetOptions.shiftAnchor(anchor, 1, -1), DateTime(2026, 11, 1));
  });

  test('widget action parsing covers taps and nav buttons', () {
    expect(parseWeekWidgetAction(null), isNull);
    expect(parseWeekWidgetAction('new_task'), isNull);
    expect(parseWeekWidgetAction('calendar/today')!.nav, WeekWidgetNav.today);
    expect(parseWeekWidgetAction('calendar')!.nav, WeekWidgetNav.today);
    expect(parseWeekWidgetAction('calendar/prev')!.nav, WeekWidgetNav.prev);
    expect(parseWeekWidgetAction('calendar/next')!.nav, WeekWidgetNav.next);
    final day = parseWeekWidgetAction('calendar/2026-11-04')!;
    expect(day.nav, WeekWidgetNav.day);
    expect(day.day, DateTime(2026, 11, 4));
    expect(parseWeekWidgetAction('calendar/bogus'), isNull);
    expect(parseWeekWidgetAction('other/thing'), isNull);
  });

  test('options persist and reload from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const options = WeekWidgetOptions(
      theme: WeekWidgetTheme.dark,
      dayCount: 3,
      anchorDayKey: '2026-11-02',
    );
    await options.save();
    final loaded = await WeekWidgetOptions.load();
    expect(loaded.theme, WeekWidgetTheme.dark);
    expect(loaded.dayCount, 3);
    expect(loaded.anchorDayKey, '2026-11-02');

    await loaded.copyWith(anchorDayKey: () => null).save();
    final reset = await WeekWidgetOptions.load();
    expect(reset.anchorDayKey, isNull);
    expect(reset.theme, WeekWidgetTheme.dark);
  });

  test('day-count buckets and titles stay consistent', () {
    final start = DateTime(2026, 11, 2);
    for (final count in [1, 3, 5, 7]) {
      final days = buildWeekCalendar(
        occurrences: const [],
        weekStart: start,
        dayCount: count,
      );
      expect(days.length, count);
      expect(days.first.date, start);
      expect(days.last.date, start.add(Duration(days: count - 1)));
    }
    expect(weekCalendarTitle(start, dayCount: 1), 'Nov 2, 2026');
    expect(weekCalendarTitle(start, dayCount: 7), 'Nov 2-8');
    // Timed events clip to the visible range.
    final days = buildWeekCalendar(
      occurrences: [
        OccurrenceCacheData(
          id: '1',
          eventId: 'e1',
          title: 'Standup',
          colorId: '1',
          startUtc: DateTime(2026, 11, 4, 9).millisecondsSinceEpoch,
          endUtc: DateTime(2026, 11, 4, 10).millisecondsSinceEpoch,
          dayKey: '2026-11-04',
          sourceType: 'event',
        ),
      ],
      weekStart: start,
      dayCount: 3,
    );
    expect(days.length, 3);
    expect(days[2].timedItems.single.title, 'Standup');
  });

  for (final theme in WeekWidgetTheme.values) {
    testWidgets('week image paints ${theme.name} theme', (tester) async {
      final days = buildWeekCalendar(
        occurrences: const [],
        weekStart: DateTime(2026, 11, 2),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 720,
            height: 360,
            child: WeekCalendarImage(
              days: days,
              now: DateTime(2026, 11, 3, 12),
              theme: theme,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('week image paints 3-day range', (tester) async {
    final days = buildWeekCalendar(
      occurrences: const [],
      weekStart: DateTime(2026, 11, 2),
      dayCount: 3,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 720,
          height: 360,
          child: WeekCalendarImage(days: days, now: DateTime(2026, 11, 3)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
