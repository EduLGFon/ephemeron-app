// Shared day math, occurrence filters, event colors, and per-day placements.
// Used by the timeline view, event blocks, and interaction handling.
import 'package:flutter/material.dart';

import '../../../../core/time/time.dart';
import '../../../../data/drift/app_database.dart';
import '../../../../domain/habits/habit_calendar_entry.dart';
import '../../application/calendar_state.dart';
import '../google_calendar_colors.dart';
import 'timeline_layout.dart';

/// Day columns rendered around the visible range for swipes.
const int timelineBufferDays = calendarDayBufferDays;

int timelineStripCount(int dayCount) => dayCount + timelineBufferDays * 2;

DateTime timelineStripAnchor(DateTime anchor) =>
    timelineDayStart(anchor, -timelineBufferDays);

DateTime timelineDayStart(DateTime anchor, int index) {
  return DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
  ).add(Duration(days: index));
}

DateTime timelineDayStartForKey(
  DateTime anchor,
  int dayCount,
  String dayKeyValue,
) {
  for (var i = 0; i < dayCount; i++) {
    final d = timelineDayStart(anchor, i);
    if (dateKey(d) == dayKeyValue) return d;
  }
  return timelineDayStart(anchor, 0);
}

int timelineDayIndex(DateTime anchor, int dayCount, String dayKeyValue) {
  for (var i = 0; i < dayCount; i++) {
    if (dateKey(timelineDayStart(anchor, i)) == dayKeyValue) return i;
  }
  return 0;
}

double timelineMinutesOf(DateTime t, DateTime midnight) =>
    t.difference(midnight).inSeconds / 60.0;

bool timelineIsVisibleDay(DateTime anchor, int dayCount, String dayKeyValue) {
  for (var i = 0; i < dayCount; i++) {
    if (dateKey(timelineDayStart(anchor, i)) == dayKeyValue) return true;
  }
  return false;
}

bool timelineIsAllDay(OccurrenceCacheData o) {
  return (o.endUtc - o.startUtc) >= const Duration(hours: 23).inMilliseconds;
}

/// True when the occurrence has fully ended (attended/past).
/// Synchronous on cached timestamps so styling works with no attendee data.
bool timelineIsPast(OccurrenceCacheData o, {int? nowMs}) {
  final now = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
  return o.endUtc < now;
}

Color timelineEventColor(BuildContext context, String? colorId) {
  if (colorId != null && colorId.isNotEmpty) {
    final parsed = googleCalendarColors[colorId] ?? tryParseCssHex(colorId);
    if (parsed != null) return parsed;
  }
  return Theme.of(context).colorScheme.primary;
}

/// Height used for a timed habit block in the hourly grid.
const double timelineHabitBlockMinutes = 30;

/// Distinct layout key for a habit entry. Event ids come from occurrence row
/// ids, so the prefix keeps habit and event placements from colliding.
String timelineHabitItemId(HabitCalendarEntry entry) =>
    'habit:${entry.habitId}@${entry.dayKey}';

/// Normalized [0, 1] horizontal rects for one day column, keyed by
/// occurrence row id (not event id, so recurring instances stay distinct)
/// and by [timelineHabitItemId] for timed habit entries. Events and habits
/// share one lane layout so overlaps split the same width.
Map<String, TimelinePlacement> timelinePlacementsFor({
  required DateTime anchor,
  required int dayCount,
  required List<OccurrenceCacheData> timed,
  List<HabitCalendarEntry> timedHabits = const [],
}) {
  final out = <String, TimelinePlacement>{};
  final byDay = <String, List<OccurrenceCacheData>>{};
  for (final o in timed) {
    byDay.putIfAbsent(o.dayKey, () => []).add(o);
  }
  final habitsByDay = <String, List<HabitCalendarEntry>>{};
  for (final h in timedHabits) {
    if (h.timeMinutes == null) continue;
    habitsByDay.putIfAbsent(h.dayKey, () => []).add(h);
  }
  final days = {...byDay.keys, ...habitsByDay.keys};
  for (final dayKeyValue in days) {
    final midnight = timelineDayStartForKey(anchor, dayCount, dayKeyValue);
    final items = <TimelineItem>[];
    for (final o in byDay[dayKeyValue] ?? const <OccurrenceCacheData>[]) {
      final s = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
      final e = DateTime.fromMillisecondsSinceEpoch(o.endUtc);
      var sMin = timelineMinutesOf(s, midnight).clamp(0.0, 1440.0);
      var eMin = timelineMinutesOf(e, midnight).clamp(0.0, 1440.0);
      if (eMin <= sMin) {
        // Spans midnight or zero-length: show at least 30min, clamp to day.
        eMin = (sMin + 30).clamp(0.0, 1440.0);
        if (eMin <= sMin) eMin = 1440.0;
      }
      items.add(TimelineItem(id: o.id, startMin: sMin, endMin: eMin));
    }
    for (final h in habitsByDay[dayKeyValue] ?? const <HabitCalendarEntry>[]) {
      final sMin = (h.timeMinutes ?? 0).clamp(0, 1440).toDouble();
      final eMin = (sMin + timelineHabitBlockMinutes).clamp(0.0, 1440.0);
      items.add(
        TimelineItem(
          id: timelineHabitItemId(h),
          startMin: sMin,
          endMin: eMin,
          canContain: false,
        ),
      );
    }
    out.addAll(layoutDayEvents(items));
  }
  return out;
}
