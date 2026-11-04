// Agenda: list grouped by day over the loaded (cache) window, filtered to
// the visible agenda range. Habit entries appear above events for each day.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/habits/habit_calendar_entry.dart';
import '../application/calendar_providers.dart';
import '../application/calendar_state.dart';
import 'agenda_event_tile.dart';
import 'event_details_sheet.dart';
import 'habit_calendar_marker.dart';

class AgendaView extends ConsumerStatefulWidget {
  const AgendaView({super.key});

  @override
  ConsumerState<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends ConsumerState<AgendaView> {
  List<OccurrenceCacheData> _lastOccurrences = const [];

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    final range = ref.watch(calendarCacheRangeProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(range));
    final building = ref.watch(calendarCacheBuildingProvider);
    final habits = ref
        .watch(calendarHabitEntriesProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <HabitCalendarEntry>[]);
    final visibleHabits = _visibleHabits(window, habits);
    return occAsync.when(
      loading: () {
        final filtered = _visible(window, _lastOccurrences);
        if (filtered.isEmpty &&
            visibleHabits.isEmpty &&
            (building || _lastOccurrences.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context, filtered, visibleHabits);
      },
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load agenda.'),
            OutlinedButton(
              onPressed: () => ref.invalidate(windowOccurrencesProvider(range)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (occs) {
        _lastOccurrences = occs;
        final filtered = _visible(window, occs);
        if (filtered.isEmpty && visibleHabits.isEmpty && building) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context, filtered, visibleHabits);
      },
    );
  }

  List<OccurrenceCacheData> _visible(
    CalendarWindow window,
    List<OccurrenceCacheData> occs,
  ) {
    final (fromKey, toKey) = _visibleKeys(window);
    return [
      for (final o in occs)
        if (o.dayKey.compareTo(fromKey) >= 0 && o.dayKey.compareTo(toKey) <= 0)
          o,
    ];
  }

  List<HabitCalendarEntry> _visibleHabits(
    CalendarWindow window,
    List<HabitCalendarEntry> habits,
  ) {
    final (fromKey, toKey) = _visibleKeys(window);
    return [
      for (final h in habits)
        if (h.dayKey.compareTo(fromKey) >= 0 && h.dayKey.compareTo(toKey) <= 0)
          h,
    ];
  }

  (String, String) _visibleKeys(CalendarWindow window) {
    final visible = window.visibleRange;
    return (
      dateKey(visible.fromUtc),
      dateKey(visible.toUtc.subtract(const Duration(milliseconds: 1))),
    );
  }

  Widget _body(
    BuildContext context,
    List<OccurrenceCacheData> occs,
    List<HabitCalendarEntry> habits,
  ) {
    if (occs.isEmpty && habits.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_outlined, size: 48),
            SizedBox(height: 8),
            Text('Nothing scheduled'),
          ],
        ),
      );
    }
    final occByDay = <String, List<OccurrenceCacheData>>{};
    for (final o in occs) {
      occByDay.putIfAbsent(o.dayKey, () => []).add(o);
    }
    final habitByDay = <String, List<HabitCalendarEntry>>{};
    for (final h in habits) {
      habitByDay.putIfAbsent(h.dayKey, () => []).add(h);
    }
    final days = {...occByDay.keys, ...habitByDay.keys}.toList()..sort();
    final items = <Widget>[];
    for (final d in days) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(d, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
      final dayHabits = habitByDay[d] ?? const <HabitCalendarEntry>[];
      dayHabits.sort((a, b) => a.habitName.compareTo(b.habitName));
      for (final h in dayHabits) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: HabitCalendarMarker(
              key: ValueKey('agenda-habit-${h.habitId}-${h.dayKey}'),
              entry: h,
            ),
          ),
        );
      }
      for (final o in occByDay[d] ?? const <OccurrenceCacheData>[]) {
        items.add(
          AgendaEventTile(
            key: ValueKey('agenda-${o.id}'),
            occurrence: o,
            onTap: (id) => showEventDetails(context, id),
          ),
        );
      }
    }
    return RepaintBoundary(
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      ),
    );
  }
}

String agendaDayKey(DateTime d) => dateKey(d);
