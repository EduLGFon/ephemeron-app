import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/services/week_calendar_data.dart';
import 'package:ephemeron/data/services/week_calendar_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('week starts on Monday unless configured otherwise', () {
    final wednesday = DateTime(2026, 11, 4);
    expect(weekStartFor(wednesday), DateTime(2026, 11, 2));
    expect(
      weekStartFor(wednesday, weekStartDay: DateTime.sunday),
      DateTime(2026, 11, 1),
    );
  });

  test('builds timed and multi-day all-day buckets', () {
    final start = DateTime(2026, 11, 2);
    final timedStart = DateTime(2026, 11, 3, 9);
    final allDayStart = DateTime(2026, 11, 5);
    final days = buildWeekCalendar(
      occurrences: [
        OccurrenceCacheData(
          id: '1',
          eventId: 'e1',
          title: 'Standup',
          colorId: '1',
          startUtc: timedStart.millisecondsSinceEpoch,
          endUtc: timedStart
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
          dayKey: '2026-11-03',
          sourceType: 'event',
        ),
        OccurrenceCacheData(
          id: '2',
          eventId: 'e2',
          title: 'Trip',
          colorId: '7',
          startUtc: allDayStart.millisecondsSinceEpoch,
          endUtc: allDayStart
              .add(const Duration(days: 2))
              .subtract(const Duration(milliseconds: 1))
              .millisecondsSinceEpoch,
          dayKey: '2026-11-05',
          sourceType: 'event',
        ),
      ],
      weekStart: start,
    );

    expect(days.length, 7);
    expect(days[1].timedItems.single.title, 'Standup');
    expect(days[3].allDayItems.single.title, 'Trip');
    expect(days[4].allDayItems.single.title, 'Trip');
    expect(days[3].allDayItems.single.allDay, isTrue);
    expect(weekCalendarTitle(start), 'Nov 2-8');
    expect(weekCalendarBody(days), contains('Tue 3: 09:00 Standup'));
  });

  testWidgets('week grid lays out with unbounded height', (tester) async {
    final start = DateTime(2026, 11, 2);
    final days = buildWeekCalendar(
      occurrences: [
        OccurrenceCacheData(
          id: '1',
          eventId: 'e1',
          title: 'Standup',
          colorId: '1',
          startUtc: DateTime(2026, 11, 3, 9).millisecondsSinceEpoch,
          endUtc: DateTime(2026, 11, 3, 10).millisecondsSinceEpoch,
          dayKey: '2026-11-03',
          sourceType: 'event',
        ),
      ],
      weekStart: start,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: WeekCalendarImage(days: days, now: DateTime(2026, 11, 3, 12)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('week grid survives tiny constraints', (tester) async {
    final days = buildWeekCalendar(
      occurrences: const [],
      weekStart: DateTime(2026, 11, 2),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 8,
            height: 8,
            child: WeekCalendarImage(days: days, now: DateTime(2026, 11, 3)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
