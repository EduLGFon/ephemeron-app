// Shared day math, occurrence filters, event colors, and per-day placements.
// Used by the timeline view, event blocks, and interaction handling.
import 'package:flutter/material.dart';

import '../../../../core/time/time.dart';
import '../../../../data/drift/app_database.dart';
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

Color timelineEventColor(BuildContext context, String? colorId) {
  if (colorId != null && colorId.isNotEmpty) {
    final parsed = googleCalendarColors[colorId] ?? tryParseCssHex(colorId);
    if (parsed != null) return parsed;
  }
  return Theme.of(context).colorScheme.primary;
}

/// Normalized [0, 1] horizontal rects for one day column, keyed by
/// occurrence row id (not event id, so recurring instances stay distinct).
Map<String, TimelinePlacement> timelinePlacementsFor({
  required DateTime anchor,
  required int dayCount,
  required List<OccurrenceCacheData> timed,
}) {
  final out = <String, TimelinePlacement>{};
  final byDay = <String, List<OccurrenceCacheData>>{};
  for (final o in timed) {
    byDay.putIfAbsent(o.dayKey, () => []).add(o);
  }
  for (final entry in byDay.entries) {
    final midnight = timelineDayStartForKey(anchor, dayCount, entry.key);
    final items = <TimelineItem>[];
    for (final o in entry.value) {
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
    out.addAll(layoutDayEvents(items));
  }
  return out;
}
