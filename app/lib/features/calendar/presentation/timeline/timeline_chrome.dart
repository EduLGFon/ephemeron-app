// Static timeline chrome: hour gutter, day headers, all-day strip.
// Pure presentation; dragging and tapping arrive via callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/habits/habit_calendar_entry.dart';
import '../habit_calendar_marker.dart';

import '../../../../core/time/device_date_format.dart';
import '../../../../core/time/time.dart';
import '../../../../data/drift/app_database.dart';
import '../../application/calendar_providers.dart';
import 'timeline_utils.dart';

class TimelineHourGutter extends StatelessWidget {
  const TimelineHourGutter({
    super.key,
    required this.hourHeight,
    required this.width,
  });

  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 24 * hourHeight,
      child: Stack(
        children: [
          for (var h = 0; h < 24; h++)
            Positioned(
              top: h * hourHeight - 7,
              right: 4,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class TimelineDayHeader extends StatelessWidget {
  const TimelineDayHeader({
    super.key,
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
    this.swipeOffset = 0,
    this.onDayTap,
  });

  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final double swipeOffset;
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        SizedBox(width: gutterWidth),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final dayWidth = cons.maxWidth / dayCount;
              final stripCount = timelineStripCount(dayCount);
              final stripAnchor = timelineStripAnchor(anchor);
              return IntrinsicHeight(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: stripCount * dayWidth,
                    maxWidth: stripCount * dayWidth,
                    child: Transform.translate(
                      offset: Offset(
                        -timelineBufferDays * dayWidth + swipeOffset,
                        0,
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < stripCount; i++)
                            SizedBox(
                              width: dayWidth,
                              child: _dayCell(
                                context,
                                timelineDayStart(stripAnchor, i),
                                now,
                                onDayTap,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    DateTime now,
    void Function(DateTime day)? onDayTap,
  ) {
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DeviceDateFormat.weekday(context, day),
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDayTap == null ? null : () => onDayTap(day),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: isToday
                  ? BoxDecoration(color: color.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${day.day}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isToday ? color.onPrimary : null,
                  fontWeight: isToday ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineAllDayStrip extends StatelessWidget {
  const TimelineAllDayStrip({
    super.key,
    required this.occs,
    this.habits = const [],
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
    required this.onTap,
    this.swipeOffset = 0,
  });

  final List<OccurrenceCacheData> occs;
  final List<HabitCalendarEntry> habits;
  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final ValueChanged<OccurrenceCacheData> onTap;
  final double swipeOffset;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutterWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'All-day',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final dayWidth = cons.maxWidth / dayCount;
              final stripCount = timelineStripCount(dayCount);
              final stripAnchor = timelineStripAnchor(anchor);
              return IntrinsicHeight(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: stripCount * dayWidth,
                    maxWidth: stripCount * dayWidth,
                    child: Transform.translate(
                      offset: Offset(
                        -timelineBufferDays * dayWidth + swipeOffset,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < stripCount; i++)
                            SizedBox(
                              width: dayWidth,
                              child: _dayChips(context, stripAnchor, i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayChips(BuildContext context, DateTime stripAnchor, int i) {
    final day = timelineDayStart(stripAnchor, i);
    final key = dateKey(day);
    final mine = occs.where((o) => o.dayKey == key).take(3).toList();
    final allHabits = habits.where((h) => h.dayKey == key).toList();
    final myHabits = allHabits.take(3).toList();
    final hiddenHabits = allHabits.length - myHabits.length;
    if (mine.isEmpty && allHabits.isEmpty) return const SizedBox(height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in mine) _AllDayChip(occurrence: o, onTap: onTap),
        for (final h in myHabits)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
            child: HabitCalendarMarker(entry: h, compact: false),
          ),
        if (hiddenHabits > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
            child: Text(
              '+$hiddenHabits habits',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Single all-day chip: past chips are dimmed, declined ones stay hollow
/// (blank inside, border + title only), matching the timed event blocks.
class _AllDayChip extends ConsumerWidget {
  const _AllDayChip({required this.occurrence, required this.onTap});

  final OccurrenceCacheData occurrence;
  final ValueChanged<OccurrenceCacheData> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rsvpAsync = ref.watch(selfRsvpForEventProvider(occurrence.eventId));
    final rsvp = rsvpAsync.maybeWhen(data: (v) => v, orElse: () => null);
    final past = timelineIsPast(occurrence);
    final hollow = rsvp == 'declined';
    final c = timelineEventColor(context, occurrence.colorId);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: InkWell(
        onTap: () => onTap(occurrence),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: hollow
                ? Colors.transparent
                : c.withValues(alpha: past ? 0.35 : 0.85),
            borderRadius: BorderRadius.circular(4),
            border: hollow
                ? Border.all(
                    color: c.withValues(alpha: past ? 0.3 : 0.6),
                    width: 1,
                  )
                : past
                ? Border.all(color: c.withValues(alpha: 0.25), width: 1)
                : null,
          ),
          child: Text(
            occurrence.title ?? 'All-day',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: hollow
                  ? scheme.onSurface.withValues(alpha: past ? 0.5 : 0.7)
                  : past
                  ? scheme.onSurface.withValues(alpha: 0.6)
                  : scheme.onPrimary,
              decoration: hollow ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}
