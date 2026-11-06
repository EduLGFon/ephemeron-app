// Month grid with per-day event rows and the selected-day agenda below.
import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/habits/habit_calendar_entry.dart';
import '../application/calendar_providers.dart';
import '../application/calendar_state.dart';
import 'agenda_event_tile.dart';
import 'event_details_sheet.dart';
import 'task_action_sheet.dart';
import 'google_calendar_colors.dart';
import 'habit_calendar_marker.dart';
import 'timeline/timeline_utils.dart';

part 'month_view/month_agenda.dart';
part 'month_view/month_grid.dart';

class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key});

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  late final ScrollController _scroll = ScrollController();
  List<OccurrenceCacheData> _lastOccurrences = const [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    final range = ref.watch(calendarCacheRangeProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(range));
    final building = ref.watch(calendarCacheBuildingProvider);
    final occurrences = occAsync.maybeWhen(
      data: (v) {
        _lastOccurrences = v;
        return v;
      },
      orElse: () => _lastOccurrences,
    );
    final habitEntries = ref
        .watch(calendarHabitEntriesProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <HabitCalendarEntry>[]);
    final habitsByDay = <String, List<HabitCalendarEntry>>{};
    for (final h in habitEntries) {
      habitsByDay.putIfAbsent(h.dayKey, () => []).add(h);
    }
    final anchor = window.anchor;
    final selectedDay = DateTime(anchor.year, anchor.month, anchor.day);
    final first = DateTime(anchor.year, anchor.month, 1);
    final lead = (first.weekday - DateTime.monday + 7) % 7;
    final start = first.subtract(Duration(days: lead));
    final days = List.generate(42, (i) => start.add(Duration(days: i)));

    final byDay = <String, List<OccurrenceCacheData>>{};
    for (final o in occurrences) {
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
    final selectedHabits =
        habitsByDay[selectedKey] ?? const <HabitCalendarEntry>[];
    final hasVisibleOccurrences = days.any(
      (d) => byDay.containsKey(dateKey(d)),
    );

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
                    if (!hasVisibleOccurrences && building)
                      const LinearProgressIndicator(minHeight: 2),
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
                                  habits:
                                      habitsByDay[dateKey(
                                        days[week * 7 + dow],
                                      )] ??
                                      const <HabitCalendarEntry>[],
                                  onTap: () => ref
                                      .read(calendarStateProvider.notifier)
                                      .goTo(days[week * 7 + dow]),
                                  onDoubleTap: () {
                                    final notifier = ref.read(
                                      calendarStateProvider.notifier,
                                    );
                                    final target = days[week * 7 + dow];
                                    notifier.setView(
                                      CalendarViewKind.multiDay,
                                      dayCount: 7,
                                    );
                                    notifier.goTo(
                                      target.subtract(const Duration(days: 3)),
                                    );
                                  },
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
                count: selectedOccs.length + selectedHabits.length,
              ),
            ),
            if (selectedOccs.isEmpty && selectedHabits.isEmpty)
              const SliverToBoxAdapter(child: _EmptyAgenda())
            else ...[
              if (selectedHabits.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final h in selectedHabits)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: HabitCalendarMarker(entry: h),
                          ),
                      ],
                    ),
                  ),
                ),
              SliverList.builder(
                itemCount: selectedOccs.length,
                itemBuilder: (ctx, i) {
                  final o = selectedOccs[i];
                  return AgendaEventTile(
                    key: ValueKey('month-agenda-${o.eventId}'),
                    occurrence: o,
                    onTap: () {
                      if (o.sourceType == 'task') {
                        showTaskActionSheet(
                          context,
                          taskId: o.eventId,
                          occurrenceDate: o.dayKey,
                        );
                      } else {
                        showEventDetails(context, o.eventId);
                      }
                    },
                  );
                },
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }
}
