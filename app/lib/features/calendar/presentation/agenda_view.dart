// Agenda: list grouped by day over the loaded (cache) window, filtered to
// the visible agenda range.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';
import '../application/calendar_state.dart';
import 'agenda_event_tile.dart';
import 'event_details_sheet.dart';

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
    return occAsync.when(
      loading: () {
        final filtered = _visible(window, _lastOccurrences);
        if (filtered.isEmpty && (building || _lastOccurrences.isEmpty)) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context, filtered);
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
        if (filtered.isEmpty && building) {
          return const Center(child: CircularProgressIndicator());
        }
        return _body(context, filtered);
      },
    );
  }

  List<OccurrenceCacheData> _visible(
    CalendarWindow window,
    List<OccurrenceCacheData> occs,
  ) {
    final visible = window.visibleRange;
    final fromKey = dateKey(visible.fromUtc);
    final toKey = dateKey(
      visible.toUtc.subtract(const Duration(milliseconds: 1)),
    );
    return [
      for (final o in occs)
        if (o.dayKey.compareTo(fromKey) >= 0 && o.dayKey.compareTo(toKey) <= 0)
          o,
    ];
  }

  Widget _body(BuildContext context, List<OccurrenceCacheData> occs) {
    if (occs.isEmpty) {
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
    final byDay = <String, List<OccurrenceCacheData>>{};
    for (final o in occs) {
      byDay.putIfAbsent(o.dayKey, () => []).add(o);
    }
    final days = byDay.keys.toList()..sort();
    final items = <Widget>[];
    for (final d in days) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(d, style: Theme.of(context).textTheme.titleSmall),
        ),
      );
      for (final o in byDay[d]!) {
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
