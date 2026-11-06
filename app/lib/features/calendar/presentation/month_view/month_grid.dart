part of '../month_view.dart';

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (final n in names)
          Expanded(
            child: Center(
              child: Text(n, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.isPastDay,
    required this.occurrences,
    this.habits = const <HabitCalendarEntry>[],
    required this.onTap,
    this.onDoubleTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool isPastDay;
  final List<OccurrenceCacheData> occurrences;
  final List<HabitCalendarEntry> habits;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;
    final dimmed = !inMonth || isPastDay;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${DeviceDateFormat.monthName(context, day.month)} ${day.day}, '
          '${occurrences.length} events',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: 0.12) : null,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: LayoutBuilder(
            builder: (ctx, c) {
              const dayNumberHeight = 20.0;
              const pillHeight = 16.0;
              const pillGap = 2.0;
              var slots =
                  ((c.maxHeight - dayNumberHeight - 4) / (pillHeight + pillGap))
                      .floor();
              if (slots < 1) slots = 1;
              final items = <Object>[...occurrences, ...habits];
              final total = items.length;
              final overflow = total > slots;
              final visibleCount = overflow ? slots - 1 : total;
              final visible = items.take(visibleCount).toList();
              final hidden = total - visibleCount;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: dayNumberHeight,
                    child: Center(
                      child: GestureDetector(
                        key: Key('month-day-number-${dateKey(day)}'),
                        behavior: HitTestBehavior.opaque,
                        onDoubleTap: onDoubleTap,
                        child: _DayNumber(day: day),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  for (var i = 0; i < visible.length; i++) ...[
                    if (visible[i] is OccurrenceCacheData)
                      _MonthPill(
                        occurrence: visible[i] as OccurrenceCacheData,
                        dimmed: dimmed,
                      )
                    else
                      HabitCalendarMarker(
                        key: ValueKey(
                          'month-habit-'
                          '${(visible[i] as HabitCalendarEntry).habitId}-'
                          '${(visible[i] as HabitCalendarEntry).dayKey}',
                        ),
                        entry: visible[i] as HabitCalendarEntry,
                        compact: true,
                      ),
                    if (i != visible.length - 1 || overflow)
                      const SizedBox(height: pillGap),
                  ],
                  if (overflow)
                    Text(
                      '+$hidden more',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: onSurface.withValues(alpha: inMonth ? 0.6 : 0.4),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day});

  final DateTime day;

  bool get _isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Text(
      '${day.day}',
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: _isToday ? scheme.onPrimary : null),
    );
    if (!_isToday) return text;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
      child: text,
    );
  }
}

class _MonthPill extends ConsumerWidget {
  const _MonthPill({required this.occurrence, required this.dimmed});

  final OccurrenceCacheData occurrence;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref
        .watch(occurrenceSourceMapProvider)
        .maybeWhen(data: (map) => map[occurrence.eventId], orElse: () => null);
    final scheme = Theme.of(context).colorScheme;
    final base = googleCalendarColor(
      occurrence.colorId ?? '',
      fallback: scheme.primary,
    );
    final color = dimmed ? base.withValues(alpha: 0.4) : base;
    final pill = Container(
      height: 16,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dimmed ? 0.1 : 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(4),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              occurrence.title ?? '…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                height: 1.2,
                color: dimmed
                    ? scheme.onSurface.withValues(alpha: 0.55)
                    : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    return Tooltip(message: source?.label ?? '', child: pill);
  }
}
