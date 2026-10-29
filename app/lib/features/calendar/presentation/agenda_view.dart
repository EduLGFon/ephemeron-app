// Agenda: infinite-ish list grouped by day over the loaded window.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';

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
              onPressed: () => ref.invalidate(windowOccurrencesProvider(window)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (occs) {
        if (occs.isEmpty) {
          return const Center(child: Text('Nothing scheduled'));
        }
        final byDay = <String, List<OccurrenceCacheData>>{};
        for (final o in occs) {
          byDay.putIfAbsent(o.dayKey, () => []).add(o);
        }
        final days = byDay.keys.toList()..sort();
        return ListView(
          children: [
            for (final d in days) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(d, style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final o in byDay[d]!)
                FutureBuilder<Event?>(
                  future: _event(ref, o.eventId),
                  builder: (ctx, snap) {
                    final t = snap.data?.title ?? '…';
                    final s = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
                    return ListTile(
                      title: Text(t),
                      trailing: Text(
                          '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}'),
                    );
                  },
                ),
            ],
          ],
        );
      },
    );
  }

  Future<Event?> _event(WidgetRef ref, String id) {
    final repo = ref.read(eventRepositoryProvider);
    return (repo.dbSelect()..where((e) => e.id.equals(id)))
        .getSingleOrNull();
  }
}

String agendaDayKey(DateTime d) => dateKey(d);
