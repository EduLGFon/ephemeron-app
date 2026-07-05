import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../application/calendar_providers.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_event.dart';
import 'event_form_sheet.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focusedMonth = ref.watch(focusedMonthProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final monthEventsAsync = ref.watch(monthEventsProvider(focusedMonth));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: monthEventsAsync.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: monthEventsAsync.isLoading
                ? null
                : () => ref.invalidate(monthEventsProvider(focusedMonth)),
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar<CalendarEvent>(
            firstDay: DateTime.utc(2015, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: focusedMonth,
            selectedDayPredicate: (day) => isSameDay(day, selectedDay),
            eventLoader: (day) => ref.read(dayEventsProvider(day)),
            onDaySelected: (selected, focused) {
              ref.read(selectedDayProvider.notifier).state = DateTime(
                selected.year,
                selected.month,
                selected.day,
              );
              final normalizedFocused = DateTime(
                focused.year,
                focused.month,
                1,
              );
              if (normalizedFocused != focusedMonth) {
                ref.read(focusedMonthProvider.notifier).state =
                    normalizedFocused;
              }
            },
            onPageChanged: (focused) {
              ref.read(focusedMonthProvider.notifier).state = DateTime(
                focused.year,
                focused.month,
                1,
              );
            },
            onFormatChanged: (_) {},
            calendarStyle: const CalendarStyle(
              markerDecoration: BoxDecoration(shape: BoxShape.circle),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _DayAgenda(
              day: selectedDay,
              monthEventsAsync: monthEventsAsync,
            ),
          ),
        ],
      ),
      // No per-screen FAB — see AppShell/QuickAddSheet (Step 5). Editing
      // an existing event still opens the fuller EventFormSheet directly
      // via _EventTile.onTap below.
    );
  }
}

class _DayAgenda extends ConsumerWidget {
  const _DayAgenda({required this.day, required this.monthEventsAsync});

  final DateTime day;
  final AsyncValue<List<CalendarEvent>> monthEventsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return monthEventsAsync.when(
      data: (_) {
        final events = ref.watch(dayEventsProvider(day));
        if (events.isEmpty) {
          return Center(
            child: Text(
              'No events',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }
        final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
        return ListView.builder(
          itemCount: sorted.length,
          itemBuilder: (context, index) => _EventTile(event: sorted[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error is CalendarNotConnectedException
                ? 'Connect Google Calendar in Settings to see your events.'
                : 'Could not load events: $error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = GoogleEventColor.options.firstWhere(
      (c) => c.id == event.colorId,
      orElse: () => GoogleEventColor.options[6],
    );

    return ListTile(
      leading: CircleAvatar(backgroundColor: Color(color.hex), radius: 8),
      title: Text(event.title),
      subtitle: Text(
        event.isAllDay
            ? 'All day'
            : '${_formatTime(event.start)} – ${_formatTime(event.end)}'
                  '${event.location != null ? ' · ${event.location}' : ''}',
      ),
      onTap: () => showEventFormSheet(
        context,
        initialDay: event.start,
        existingEvent: event,
      ),
      onLongPress: () => _confirmDelete(context, ref),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(event.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(calendarRepositoryProvider).deleteEvent(event.id);
    ref.invalidate(
      monthEventsProvider(DateTime(event.start.year, event.start.month, 1)),
    );
  }
}
