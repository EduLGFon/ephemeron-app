// Positioned event/task bubble on the timeline day grid.
// Computes its own geometry from the occurrence, day, and overlap placement.
// Nested children (inside a bigger event) get a contrasting outline.
// Pure presentation; dragging and tapping arrive via callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/drift/app_database.dart';
import '../../application/calendar_providers.dart';
import 'timeline_layout.dart';
import 'timeline_utils.dart';

class TimelineEventBlock extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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

    final rsvpAsync = ref.watch(selfRsvpForEventProvider(occurrence.eventId));
    final rsvp = rsvpAsync.maybeWhen(data: (v) => v, orElse: () => null);
    final source = ref
        .watch(occurrenceSourceMapProvider)
        .maybeWhen(data: (map) => map[occurrence.eventId], orElse: () => null);
    // Past = already attended/ended. Synchronous so it always shows,
    // even when attendee rows are missing.
    final isPast = timelineIsPast(occurrence);
    final scheme = Theme.of(context).colorScheme;
    // Declined (not attending) stays hollow: blank inside, border + title.
    final hollow = rsvp == 'declined';

    // Base fill: past events are dimmed, RSVP adjusts further.
    double fillAlpha = nested ? 0.95 : 0.85;
    if (isPast) fillAlpha = 0.35;
    if (rsvp == 'tentative') fillAlpha = (fillAlpha * 0.7).clamp(0.0, 1.0);
    if (hollow) fillAlpha = 0.0;

    Color textColor = scheme.onPrimary;
    FontWeight? weight;
    TextDecoration? decoration;
    if (isPast && rsvp != 'accepted') {
      textColor = scheme.onSurface.withValues(alpha: 0.55);
    }
    if (hollow) {
      decoration = TextDecoration.lineThrough;
      textColor = scheme.onSurface.withValues(alpha: isPast ? 0.5 : 0.7);
    } else if (rsvp == 'accepted' && isPast) {
      // Attended: keep readable, mark with bolder text.
      textColor = scheme.onPrimary;
      weight = FontWeight.w600;
    }

    BoxBorder? border;
    if (hollow) {
      border = Border.all(
        color: base.withValues(alpha: isPast ? 0.3 : 0.6),
        width: 1,
      );
    } else if (rsvp == 'accepted') {
      border = Border.all(
        color: isPast ? scheme.primary.withValues(alpha: 0.45) : scheme.primary,
        width: 1.5,
      );
    } else if (isPast) {
      border = Border.all(color: base.withValues(alpha: 0.25), width: 1);
    } else if (nested) {
      border = Border.all(
        color: scheme.surface.withValues(alpha: 0.9),
        width: 1,
      );
    }

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
            color: base.withValues(alpha: fillAlpha),
            borderRadius: BorderRadius.circular(4),
            border: border,
          ),
          child: Text.rich(
            TextSpan(
              text: occurrence.title ?? '…',
              children: [
                if (source != null && y1 - y0 >= 48 && !hollow)
                  TextSpan(
                    text: '\n${source.label}',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.75),
                      fontSize: 9,
                      fontWeight: FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
              ],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: weight,
              decoration: decoration,
            ),
          ),
        ),
      ),
    );
  }
}
