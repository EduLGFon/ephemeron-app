import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_palettes.dart';
import '../domain/calendar_event.dart';
import '../application/calendar_providers.dart';
import 'calendar_event_tile.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';
import '../data/calendar_repository.dart';

class CalendarDayAgenda extends ConsumerWidget {
  const CalendarDayAgenda({
    super.key,
    required this.day,
    required this.monthEventsAsync,
    required this.palette,
  });

  final DateTime day;
  final AsyncValue<List<CalendarEvent>> monthEventsAsync;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return monthEventsAsync.when(
      data: (_) {
        final events = ref.watch(dayEventsProvider(day));
        if (events.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy,
                    size: 64, color: palette.text.withValues(alpha: 0.1)),
                const SizedBox(height: 16),
                Text(
                  'No events for this day',
                  style: TextStyle(
                      color: palette.text.withValues(alpha: 0.5), fontSize: 16),
                ),
              ],
            ),
          );
        }
        final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: sorted.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: RepaintBoundary(
              child: CalendarEventTile(event: sorted[index], palette: palette),
            ),
          ),
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error is CalendarNotConnectedException
                ? 'Connect Google Calendar in Settings to see your events.'
                : 'Could not load events: \$error',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.text),
          ),
        ),
      ),
    );
  }
}
