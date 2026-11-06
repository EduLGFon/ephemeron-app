part of '../timeline_chrome.dart';

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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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
