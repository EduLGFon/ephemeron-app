// Shared agenda event tile used by the full agenda and the month agenda.
// Styling (color bar, RSVP, past dimming) stays identical in both places.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';
import 'calendar_source_picker.dart';
import 'timeline/timeline_utils.dart';

class AgendaEventTile extends ConsumerWidget {
  const AgendaEventTile({super.key, required this.occurrence, this.onTap});

  final OccurrenceCacheData occurrence;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rsvpAsync = ref.watch(selfRsvpForEventProvider(occurrence.eventId));
    final rsvp = rsvpAsync.maybeWhen(data: (v) => v, orElse: () => null);
    final source = ref
        .watch(occurrenceSourceMapProvider)
        .maybeWhen(data: (map) => map[occurrence.eventId], orElse: () => null);
    final baseColor = timelineEventColor(context, occurrence.colorId);
    final isPast = timelineIsPast(occurrence);
    final scheme = Theme.of(context).colorScheme;

    double barAlpha = 1.0;
    if (isPast) barAlpha = 0.35;
    if (rsvp == 'tentative') barAlpha *= 0.6;
    if (rsvp == 'declined') barAlpha *= 0.5;

    TextStyle? titleStyle;
    if (rsvp == 'declined') {
      titleStyle = TextStyle(
        decoration: TextDecoration.lineThrough,
        color: scheme.onSurface.withValues(alpha: 0.5),
      );
    } else if (isPast && rsvp != 'accepted') {
      titleStyle = TextStyle(color: scheme.onSurface.withValues(alpha: 0.55));
    } else if (rsvp == 'tentative') {
      titleStyle = TextStyle(color: scheme.onSurface.withValues(alpha: 0.7));
    } else if (isPast) {
      // Attended past event: dimmed but still marked attending.
      titleStyle = TextStyle(
        color: scheme.onSurface.withValues(alpha: 0.75),
        fontWeight: FontWeight.w600,
      );
    }

    final allDay = timelineIsAllDay(occurrence);
    final trailingText = allDay
        ? 'All-day'
        : DeviceDateFormat.time(
            context,
            DateTime.fromMillisecondsSinceEpoch(occurrence.startUtc),
          );

    return ListTile(
      onTap: onTap == null ? null : () => onTap!(occurrence.eventId),
      leading: Container(
        width: 4,
        height: 36,
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: barAlpha),
          borderRadius: BorderRadius.circular(2),
          border: rsvp == 'accepted'
              ? Border.all(color: scheme.primary, width: 1)
              : null,
        ),
      ),
      title: Text(occurrence.title ?? '…', style: titleStyle),
      subtitle: source == null
          ? null
          : InkWell(
              onTap: () => pickAndMoveEvent(
                context,
                ref,
                eventId: occurrence.eventId,
                currentCalendarId: source.calendarId,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      source.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.swap_horiz, size: 14),
                ],
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rsvp == 'accepted')
            Icon(Icons.check, size: 16, color: scheme.primary),
          if (rsvp == 'declined')
            Icon(
              Icons.close,
              size: 16,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          Text(trailingText),
        ],
      ),
    );
  }
}
