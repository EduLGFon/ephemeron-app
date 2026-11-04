// Agenda: infinite-ish list grouped by day over the loaded window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';
import 'agenda_event_tile.dart';
import 'event_details_sheet.dart';

class AgendaView extends ConsumerWidget {
  const AgendaView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    return occAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load agenda.'),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(windowOccurrencesProvider(window)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (occs) {
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
      },
    );
  }
}

String agendaDayKey(DateTime d) => dateKey(d);
