// Pure data shaping for the home-screen week calendar widget.
// Turns occurrence-cache rows into seven day buckets with all-day and timed
// items. Kept free of Riverpod so foreground and headless widget pushes can
// share the exact same layout.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/presentation/google_calendar_colors.dart';
import '../drift/app_database.dart';

class WeekCalendarItem {
  const WeekCalendarItem({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.color,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final Color color;
}

class WeekCalendarDay {
  const WeekCalendarDay({required this.date, required this.items});

  final DateTime date;
  final List<WeekCalendarItem> items;

  List<WeekCalendarItem> get allDayItems =>
      items.where((i) => i.allDay).toList(growable: false);

  List<WeekCalendarItem> get timedItems =>
      items.where((i) => !i.allDay).toList(growable: false);
}

/// Start of the week containing [now] for the configured first weekday
/// ([weekStartDay] uses Dart's DateTime.monday..sunday constants).
DateTime weekStartFor(DateTime now, {int weekStartDay = DateTime.monday}) {
  final day = DateTime(now.year, now.month, now.day);
  final delta = (day.weekday - weekStartDay) % 7;
  return day.subtract(Duration(days: delta));
}

/// Builds seven day buckets for [weekStart]. All-day rows are repeated on
/// every day they cover so a multi-day event is visible across the week.
List<WeekCalendarDay> buildWeekCalendar({
  required List<OccurrenceCacheData> occurrences,
  required DateTime weekStart,
}) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final buckets = List.generate(7, (_) => <WeekCalendarItem>[]);

  for (final o in occurrences) {
    final title = (o.title ?? '').trim();
    final rawColor = (o.colorId == null || o.colorId!.isEmpty)
        ? stablePaletteIdFor('occ:${o.eventId}')
        : o.colorId!;
    final color = googleCalendarColor(
      rawColor,
      fallback: const Color(0xFF039BE5),
    );
    final itemStart = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
    final itemEnd = DateTime.fromMillisecondsSinceEpoch(o.endUtc);
    final durationMs = o.endUtc - o.startUtc;
    final allDay = durationMs >= const Duration(hours: 23).inMilliseconds;

    if (allDay) {
      // All-day rows carry their semantic date in dayKey; day and multi-day
      // events are stored in UTC, while some all-day tasks use local
      // midnight, so converting the timestamp directly can shift a day.
      final first =
          DateTime.tryParse(o.dayKey) ??
          DateTime(itemStart.year, itemStart.month, itemStart.day);
      final spanDays = (durationMs ~/ Duration.millisecondsPerDay + 1)
          .clamp(1, 370)
          .toInt();
      for (var offset = 0; offset < spanDays; offset++) {
        final day = DateTime(
          first.year,
          first.month,
          first.day,
        ).add(Duration(days: offset));
        final index = day.difference(start).inDays;
        if (index >= 0 && index < 7) {
          buckets[index].add(
            WeekCalendarItem(
              title: title.isEmpty ? 'Untitled' : title,
              start: day,
              end: day.add(const Duration(days: 1)),
              allDay: true,
              color: color,
            ),
          );
        }
      }
      continue;
    }

    for (var i = 0; i < 7; i++) {
      final dayStart = start.add(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));
      if (!itemStart.isBefore(dayEnd) || !itemEnd.isAfter(dayStart)) continue;
      final clippedStart = itemStart.isBefore(dayStart) ? dayStart : itemStart;
      final clippedEnd = itemEnd.isAfter(dayEnd) ? dayEnd : itemEnd;
      buckets[i].add(
        WeekCalendarItem(
          title: title.isEmpty ? 'Untitled' : title,
          start: clippedStart,
          end: clippedEnd,
          allDay: false,
          color: color,
        ),
      );
    }
  }

  for (final bucket in buckets) {
    bucket.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
  }

  return [
    for (var i = 0; i < 7; i++)
      WeekCalendarDay(
        date: start.add(Duration(days: i)),
        items: buckets[i],
      ),
  ];
}

/// Compact title shown above the week grid.
String weekCalendarTitle(DateTime weekStart) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end = start.add(const Duration(days: 6));
  if (start.year != end.year) {
    return '${DateFormat.yMMMd().format(start)} - '
        '${DateFormat.yMMMd().format(end)}';
  }
  if (start.month == end.month) {
    return '${DateFormat.MMM().format(start)} ${start.day}-${end.day}';
  }
  return '${DateFormat.MMMd().format(start)} - '
      '${DateFormat.MMMd().format(end)}';
}

/// Text fallback for launchers that cannot render the image.
String weekCalendarBody(List<WeekCalendarDay> days) {
  if (!days.any((d) => d.items.isNotEmpty)) return 'No events this week.';
  final lines = <String>[];
  for (final day in days) {
    final label = '${DateFormat.E().format(day.date)} ${day.date.day}';
    if (day.items.isEmpty) {
      lines.add('$label: -');
      continue;
    }
    final preview = day.items
        .take(4)
        .map(
          (i) => i.allDay
              ? i.title
              : '${DateFormat.Hm().format(i.start)} ${i.title}',
        )
        .join(', ');
    final extra = day.items.length > 4 ? ' +${day.items.length - 4}' : '';
    lines.add('$label: $preview$extra');
  }
  return lines.join('\n');
}
