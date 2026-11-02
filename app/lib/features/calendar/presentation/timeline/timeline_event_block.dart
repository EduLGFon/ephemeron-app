// Positioned event/task bubble on the timeline day grid.
// Computes its own geometry from the occurrence, day, and overlap placement.
// Nested children (inside a bigger event) get a contrasting outline.
// Pure presentation; dragging and tapping arrive via callbacks.
import 'package:flutter/material.dart';

import '../../../../data/drift/app_database.dart';
import 'timeline_layout.dart';
import 'timeline_utils.dart';

class TimelineEventBlock extends StatelessWidget {
  const TimelineEventBlock({
    super.key,
    required this.occurrence,
    required this.anchor,
    required this.dayCount,
    required this.dayIndex,
    required this.columnWidth,
    required this.hourHeight,
    required this.placement,
    required this.yOffset,
    required this.leftShift,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  final OccurrenceCacheData occurrence;
  final DateTime anchor;
  final int dayCount;
  final int dayIndex;
  final double columnWidth;
  final double hourHeight;
  final TimelinePlacement? placement;
  final double yOffset;
  final double leftShift;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;
  final VoidCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final midnight = timelineDayStart(anchor, dayIndex);
    final s = DateTime.fromMillisecondsSinceEpoch(occurrence.startUtc);
    final e = DateTime.fromMillisecondsSinceEpoch(occurrence.endUtc);
    var sMin = timelineMinutesOf(s, midnight).clamp(0.0, 1440.0);
    var eMin = timelineMinutesOf(e, midnight).clamp(0.0, 1440.0);
    if (eMin <= sMin) eMin = (sMin + 30).clamp(0.0, 1440.0);
    var y0 = sMin / 60 * hourHeight + yOffset;
    var y1 = eMin / 60 * hourHeight + yOffset;
    if (y1 - y0 < 20) y1 = y0 + 20;

    final laneW = columnWidth - 4;
    final fracLeft = placement?.left ?? 0.0;
    final fracWidth = placement?.width ?? 1.0;
    final left = dayIndex * columnWidth + 2 + fracLeft * laneW + leftShift;
    var width = fracWidth * laneW - 2;
    if (width < 14) width = 14;
    final depth = placement?.depth ?? 0;
    final nested = depth > 0;
    final base = timelineEventColor(context, occurrence.colorId);

    return Positioned(
      left: left,
      top: y0,
      width: width,
      height: y1 - y0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: (_) => onLongPressStart(),
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: (_) => onLongPressEnd(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: base.withValues(alpha: nested ? 0.95 : 0.85),
            borderRadius: BorderRadius.circular(4),
            border: nested
                ? Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    width: 1,
                  )
                : null,
          ),
          child: Text(
            occurrence.title ?? '…',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
