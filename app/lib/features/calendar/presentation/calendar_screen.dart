// Calendar screen: view switcher, navigation, rebuild-on-window-change.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ephemeron/core/time/device_date_format.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/session/session_restore.dart';
import '../../settings/application/settings_providers.dart';
import '../../sync/presentation/sync_title.dart';
import '../application/calendar_providers.dart';
import '../../tasks/application/tasks_providers.dart';
import '../application/calendar_state.dart';
import 'agenda_view.dart';
import 'calendar_settings_screen.dart';
import 'calendar_swipe.dart';
import 'event_editor_sheet.dart';
import 'month_view.dart';
import 'timeline/timeline_view.dart';
import 'year_view.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarRange? _builtRange;
  CalendarWindow? _persisted;
  bool _rebuilding = false;
  bool _rebuildAgain = false;
  Timer? _restoreFallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRebuild());
    // Safety net: if session restore never reports completion, build the
    // default window instead of leaving the calendar empty.
    _restoreFallback = Timer(const Duration(seconds: 2), () {
      if (!mounted || ref.read(initialRestoreDoneProvider)) return;
      ref.read(initialRestoreDoneProvider.notifier).markDone();
      _maybeRebuild();
    });
  }

  @override
  void dispose() {
    _restoreFallback?.cancel();
    super.dispose();
  }

  Future<void> _maybeRebuild() async {
    if (!mounted || _rebuilding) {
      if (_rebuilding) _rebuildAgain = true;
      return;
    }
    // Wait for session restore so the default window is not materialized
    // immediately before the saved view/anchor is applied.
    if (!ref.read(initialRestoreDoneProvider)) return;

    final window = ref.read(calendarStateProvider);
    // Persist every window change (including day selection in the month
    // view) without forcing a cache rebuild for it.
    if (_persisted != window) {
      _persisted = window;
      Future.microtask(() async {
        try {
          if (!mounted) return;
          await persistCalendarView(ref);
        } catch (_) {}
      });
    }

    _rebuilding = true;
    var didRebuild = false;
    try {
      do {
        _rebuildAgain = false;
        if (!mounted) break;
        final dirty = ref.read(occurrenceDirtyProvider);
        final range = ref.read(calendarCacheRangeProvider);
        if (!dirty && _builtRange == range) break;
        final building = ref.read(calendarCacheBuildingProvider.notifier);
        building.set(true);
        try {
          await ref
              .read(occurrenceRepositoryProvider)
              .rebuildWindow(
                windowStartUtc: range.fromUtc,
                windowEndUtc: range.toUtc,
              );
          _builtRange = range;
          didRebuild = true;
          if (ref.read(occurrenceDirtyProvider)) {
            ref.read(occurrenceDirtyProvider.notifier).clear();
          }
        } catch (_) {
          // Keep the previous built range so the next frame retries.
        } finally {
          if (mounted) building.set(false);
        }
      } while (_rebuildAgain && mounted);
    } finally {
      _rebuilding = false;
    }
    if (mounted && didRebuild) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final window = ref.watch(calendarStateProvider);
    ref.watch(occurrenceDirtyProvider);
    ref.watch(initialRestoreDoneProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRebuild());
    return Scaffold(
      appBar: AppBar(
        title: SyncTitle(text: 'Calendar ${_title(context, window)}'),
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
          PopupMenuButton<CalendarViewKind?>(
            icon: const Icon(Icons.view_agenda_outlined),
            onSelected: (v) {
              if (v == null) return;
              ref.read(calendarStateProvider.notifier).setView(v);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: CalendarViewKind.month,
                child: Text('Month'),
              ),
              for (final d in [3, 4, 7])
                PopupMenuItem(
                  value: null,
                  onTap: () => ref
                      .read(calendarStateProvider.notifier)
                      .setView(CalendarViewKind.multiDay, dayCount: d),
                  child: Text('$d days'),
                ),
              const PopupMenuItem(
                value: CalendarViewKind.day,
                child: Text('Day'),
              ),
              const PopupMenuItem(
                value: CalendarViewKind.agenda,
                child: Text('Agenda'),
              ),
              const PopupMenuItem(
                value: CalendarViewKind.year,
                child: Text('Year'),
              ),
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
        CalendarViewKind.month => CalendarSwipe(
          enabled: true,
          onShift: (direction) =>
              ref.read(calendarStateProvider.notifier).shiftMonths(direction),
          child: const MonthView(),
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

  String _title(BuildContext context, CalendarWindow w) =>
      DeviceDateFormat.yMMM(context).format(w.anchor);
}

Future<void> persistCalendarView(WidgetRef ref) async {
  final repo = await ref.read(settingsRepositoryProvider.future);
  final window = ref.read(calendarStateProvider);
  await repo.setCalendarView(window.view.name);
  await repo.setCalendarAnchorMs(
    DateTime.utc(
      window.anchor.year,
      window.anchor.month,
      window.anchor.day,
    ).millisecondsSinceEpoch,
  );
  await repo.setCalendarDayCount(window.dayCount);
}
