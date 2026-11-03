// Static timeline chrome: hour gutter, day headers, all-day strip.
// Pure presentation; dragging and tapping arrive via callbacks.
import 'package:flutter/material.dart';

import '../../../../core/time/device_date_format.dart';
import '../../../../core/time/time.dart';
import '../../../../data/drift/app_database.dart';
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
  });

  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final double swipeOffset;

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

  Widget _dayCell(BuildContext context, DateTime day, DateTime now) {
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
          Container(
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
        ],
      ),
    );
  }
}

class TimelineAllDayStrip extends StatelessWidget {
  const TimelineAllDayStrip({
    super.key,
    required this.occs,
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
    required this.onTap,
    this.swipeOffset = 0,
  });

  final List<OccurrenceCacheData> occs;
  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final ValueChanged<String> onTap;
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
                              child: _dayChips(stripAnchor, i),
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

  Widget _dayChips(DateTime stripAnchor, int i) {
    final day = timelineDayStart(stripAnchor, i);
    final key = dateKey(day);
    final mine = occs.where((o) => o.dayKey == key).take(3).toList();
    if (mine.isEmpty) return const SizedBox(height: 8);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in mine)
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
              child: InkWell(
                onTap: () => onTap(o.eventId),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: timelineEventColor(
                      ctx,
                      o.colorId,
                    ).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    o.title ?? 'All-day',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
