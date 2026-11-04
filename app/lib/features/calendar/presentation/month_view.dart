// Month grid with per-day event rows and the selected-day agenda below.
// The first page fills the viewport with six week rows (day number plus
// compact event bars, '+N more' on overflow); scrolling down reveals the
// agenda for the selected day, which defaults to today.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';
import 'agenda_event_tile.dart';
import 'event_details_sheet.dart';
import 'google_calendar_colors.dart';
import 'timeline/timeline_utils.dart';

class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key});

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  late final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    final anchor = window.anchor;
    final selectedDay = DateTime(anchor.year, anchor.month, anchor.day);
    final first = DateTime(anchor.year, anchor.month, 1);
    final lead = (first.weekday - DateTime.monday + 7) % 7;
    final start = first.subtract(Duration(days: lead));
    final days = List.generate(42, (i) => start.add(Duration(days: i)));

    final byDay = <String, List<OccurrenceCacheData>>{};
    for (final o in occAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <OccurrenceCacheData>[],
    )) {
      byDay.putIfAbsent(o.dayKey, () => []).add(o);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final allDayA = timelineIsAllDay(a) ? 0 : 1;
        final allDayB = timelineIsAllDay(b) ? 0 : 1;
        if (allDayA != allDayB) return allDayA.compareTo(allDayB);
        return a.startUtc.compareTo(b.startUtc);
      });
    }

    final todayKey = dateKey(DateTime.now());
    final selectedKey = dateKey(selectedDay);
    final selectedOccs = byDay[selectedKey] ?? const <OccurrenceCacheData>[];

    return LayoutBuilder(
      builder: (context, cons) {
        final viewportHeight = cons.maxHeight.isFinite ? cons.maxHeight : 600.0;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: viewportHeight,
                child: Column(
                  children: [
                    const _WeekdayHeader(),
                    for (var week = 0; week < 6; week++)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var dow = 0; dow < 7; dow++)
                              Expanded(
                                key: Key(
                                  'month-day-${dateKey(days[week * 7 + dow])}',
                                ),
                                child: _MonthDayCell(
                                  day: days[week * 7 + dow],
                                  inMonth:
                                      days[week * 7 + dow].month ==
                                      anchor.month,
                                  selected:
                                      dateKey(days[week * 7 + dow]) ==
                                      selectedKey,
                                  isPastDay:
                                      dateKey(
                                        days[week * 7 + dow],
                                      ).compareTo(todayKey) <
                                      0,
                                  occurrences:
                                      byDay[dateKey(days[week * 7 + dow])] ??
                                      const <OccurrenceCacheData>[],
                                  onTap: () => ref
                                      .read(calendarStateProvider.notifier)
                                      .goTo(days[week * 7 + dow]),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _AgendaHeader(
                day: selectedDay,
                count: selectedOccs.length,
              ),
            ),
            if (selectedOccs.isEmpty)
              const SliverToBoxAdapter(child: _EmptyAgenda())
            else
              SliverList.builder(
                itemCount: selectedOccs.length,
                itemBuilder: (ctx, i) {
                  final o = selectedOccs[i];
                  return AgendaEventTile(
                    key: ValueKey('month-agenda-${o.eventId}'),
                    occurrence: o,
                    onTap: (id) => showEventDetails(context, id),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}

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
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool isPastDay;
  final List<OccurrenceCacheData> occurrences;
  final VoidCallback onTap;

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
              final total = occurrences.length;
              final overflow = total > slots;
              final visibleCount = overflow ? slots - 1 : total;
              final visible = occurrences.take(visibleCount).toList();
              final hidden = total - visibleCount;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: dayNumberHeight,
                    child: Center(child: _DayNumber(day: day)),
                  ),
                  const SizedBox(height: 2),
                  for (var i = 0; i < visible.length; i++) ...[
                    _MonthPill(occurrence: visible[i], dimmed: dimmed),
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
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: _isToday ? scheme.onPrimary : null,
      ),
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

class _MonthPill extends StatelessWidget {
  const _MonthPill({required this.occurrence, required this.dimmed});

  final OccurrenceCacheData occurrence;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = googleCalendarColor(
      occurrence.colorId ?? '',
      fallback: scheme.primary,
    );
    final color = dimmed ? base.withValues(alpha: 0.4) : base;
    return Container(
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
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  @override
  Widget build(BuildContext context) {
    final title =
        '${DeviceDateFormat.weekdayFull(context, day)}, '
        '${DeviceDateFormat.monthName(context, day.month)} ${day.day}';
    final subtitle = count == 0
        ? 'No events'
        : count == 1
        ? '1 event'
        : '$count events';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            key: const Key('month-agenda-title'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('month-agenda-empty'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 48),
            SizedBox(height: 8),
            Text('Nothing scheduled'),
          ],
        ),
      ),
    );
  }
}
