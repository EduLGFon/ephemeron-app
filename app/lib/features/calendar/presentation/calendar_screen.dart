// Calendar screen: view switcher, navigation, rebuild-on-window-change.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_providers.dart';
import '../application/calendar_providers.dart';
import '../application/calendar_state.dart';
import 'agenda_view.dart';
import 'calendar_settings_screen.dart';
import 'event_editor_sheet.dart';
import 'month_view.dart';
import 'timeline_view.dart';
import 'year_view.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarWindow? _built;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRebuild());
  }

  Future<void> _maybeRebuild() async {
    if (!mounted) return;
    final window = ref.read(calendarStateProvider);
    if (_built == window) return;
    _built = window;
    await ref
        .read(occurrenceRepositoryProvider)
        .rebuildWindow(
          windowStartUtc: window.fromUtc,
          windowEndUtc: window.toUtc,
        );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRebuild());
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(window)),
        leading: IconButton(
          icon: const Icon(Icons.today),
          tooltip: 'Today',
          onPressed: () => ref.read(calendarStateProvider.notifier).goToday(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                ref.read(calendarStateProvider.notifier).shift(-_step(window)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                ref.read(calendarStateProvider.notifier).shift(_step(window)),
          ),
          PopupMenuButton<CalendarViewKind>(
            icon: const Icon(Icons.view_agenda_outlined),
            onSelected: (v) {
              if (v == CalendarViewKind.multiDay) {
                _pickDayCount();
                return;
              }
              ref.read(calendarStateProvider.notifier).setView(v);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: CalendarViewKind.month,
                child: Text('Month'),
              ),
              PopupMenuItem(
                value: CalendarViewKind.multiDay,
                child: Text('3/4/7 days'),
              ),
              PopupMenuItem(value: CalendarViewKind.day, child: Text('Day')),
              PopupMenuItem(
                value: CalendarViewKind.agenda,
                child: Text('Agenda'),
              ),
              PopupMenuItem(value: CalendarViewKind.year, child: Text('Year')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CalendarSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: switch (window.view) {
        CalendarViewKind.month => MonthView(
          onDayTap: (d) {
            ref.read(calendarStateProvider.notifier)
              ..goTo(d)
              ..setView(CalendarViewKind.day);
          },
        ),
        CalendarViewKind.multiDay => TimelineView(
          anchor: window.anchor,
          dayCount: window.dayCount,
        ),
        CalendarViewKind.day => TimelineView(
          anchor: window.anchor,
          dayCount: 1,
        ),
        CalendarViewKind.agenda => const AgendaView(),
        CalendarViewKind.year => const YearView(),
      },
      floatingActionButton: FloatingActionButton(
        heroTag: 'calendarFab',
        onPressed: () =>
            showEventEditor(context, initialDay: window.anchor, initialHour: 9),
        child: const Icon(Icons.add),
      ),
    );
  }

  int _step(CalendarWindow w) => switch (w.view) {
    CalendarViewKind.month => 30,
    CalendarViewKind.year => 365,
    CalendarViewKind.multiDay => w.dayCount,
    _ => 1,
  };

  String _title(CalendarWindow w) =>
      '${w.anchor.year}-${w.anchor.month.toString().padLeft(2, '0')}';

  Future<void> _pickDayCount() async {
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Days'),
        children: [
          for (final d in [3, 4, 7])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(d),
              child: Text('$d days'),
            ),
        ],
      ),
    );
    if (n != null) {
      ref
          .read(calendarStateProvider.notifier)
          .setView(CalendarViewKind.multiDay, dayCount: n);
    }
  }
}

Future<void> persistCalendarView(WidgetRef ref) async {
  final repo = await ref.read(settingsRepositoryProvider.future);
  final view = ref.read(calendarStateProvider).view;
  await repo.setCalendarView(view.name);
}
