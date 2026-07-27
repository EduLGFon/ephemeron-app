
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar_event.dart';
import 'calendar_daily_timeline_view.dart';
import 'calendar_month_grid_view.dart';
import 'calendar_multi_day_timeline_view.dart';
import 'calendar_app_bar.dart';
import 'calendar_day_agenda.dart';

import '../../sync/application/sync_service.dart';
import '../../auth/google/google_auth_provider.dart';
import 'package:ephemeron/core/widgets/app_loading_indicator.dart';

class CalendarFormatNotifier extends Notifier<CalendarFormat> {
  @override
  CalendarFormat build() => CalendarFormat.month;

  void setFormat(CalendarFormat format) {
    state = format;
  }
}

final calendarFormatProvider =
    NotifierProvider<CalendarFormatNotifier, CalendarFormat>(
  () => CalendarFormatNotifier(),
);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  static const _initialPage = 10000;
  late final PageController _monthPageController;
  late final PageController _multiDayPageController;
  late final PageController _dailyPageController;
  late final DateTime _anchorDate;

  @override
  void initState() {
    super.initState();
    _requestCalendarPermission();
    final now = DateTime.now();
    _anchorDate = DateTime(now.year, now.month, now.day);
    _monthPageController = PageController(initialPage: _initialPage);
    _multiDayPageController = PageController(initialPage: _initialPage);
    _dailyPageController = PageController(initialPage: _initialPage);
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _multiDayPageController.dispose();
    _dailyPageController.dispose();
    super.dispose();
  }

  Future<void> _requestCalendarPermission() async {
    // Permission.calendarFullAccess is supported on Android & iOS.
    // Check if the system supports it or if it's already granted.
    try {
      if (await Permission.calendarFullAccess.isDenied) {
        await Permission.calendarFullAccess.request();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(themeEngineProvider);
    final focusedMonth = ref.watch(focusedMonthProvider);
    final selectedDay = ref.watch(selectedDayProvider);
    final calendarFormat = ref.watch(calendarFormatProvider);
    final settings = ref.watch(appSettingsProvider);
    final calendarView = ref.watch(calendarViewProvider);
    final monthEventsAsync = ref.watch(monthEventsProvider(focusedMonth));

    final syncState = ref.watch(syncServiceProvider);
    final account = ref.watch(googleAccountProvider).value;
    final hasUnsynced = ref.watch(hasUnsyncedChangesProvider).value ?? false;
    final Color titleColor;
    if (account == null) {
      titleColor = palette.text;
    } else if (hasUnsynced) {
      titleColor = Colors.grey;
    } else {
      titleColor = palette.primary;
    }

    // Sync month PageController if changed externally
    final monthDiff = (focusedMonth.year - _anchorDate.year) * 12 +
        (focusedMonth.month - _anchorDate.month);
    final targetMonthPage = _initialPage + monthDiff;
    if (_monthPageController.hasClients &&
        _monthPageController.page?.round() != targetMonthPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_monthPageController.hasClients &&
            _monthPageController.page?.round() != targetMonthPage) {
          _monthPageController.jumpToPage(targetMonthPage);
        }
      });
    }

    // Sync daily PageController if changed externally
    final dayDiff = selectedDay.difference(_anchorDate).inDays;
    final targetDailyPage = _initialPage + dayDiff;
    if (_dailyPageController.hasClients &&
        _dailyPageController.page?.round() != targetDailyPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dailyPageController.hasClients &&
            _dailyPageController.page?.round() != targetDailyPage) {
          _dailyPageController.jumpToPage(targetDailyPage);
        }
      });
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          ref
              .read(calendarViewProvider.notifier)
              .setView(CalendarView.monthGrid);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          appBar: CalendarAppBar(
            palette: palette,
            syncState: syncState,
            titleColor: titleColor,
          ),
          body: calendarView == CalendarView.monthGrid
              ? Column(
                  children: [
                    // Month switcher row for the grid view
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: Icon(Icons.chevron_left, color: palette.text),
                            onPressed: () {
                              ref
                                  .read(focusedMonthProvider.notifier)
                                  .setMonth(DateTime(
                                    focusedMonth.year,
                                    focusedMonth.month - 1,
                                    1,
                                  ));
                            },
                          ),
                          Text(
                            _formatMonthYear(focusedMonth),
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon:
                                Icon(Icons.chevron_right, color: palette.text),
                            onPressed: () {
                              ref
                                  .read(focusedMonthProvider.notifier)
                                  .setMonth(DateTime(
                                    focusedMonth.year,
                                    focusedMonth.month + 1,
                                    1,
                                  ));
                            },
                          ),
                        ],
                      ),
                    ),
                    // Grid view taking full height
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: palette.surface
                              .withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: palette.text.withValues(alpha: 0.1),
                              width: 1),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: monthEventsAsync.hasValue
                              ? CalendarMonthGridView(
                                  focusedMonth: focusedMonth,
                                  selectedDay: selectedDay,
                                  events: monthEventsAsync.value!,
                                  startDayOfWeek: settings.calendarStartDay,
                                )
                              : monthEventsAsync.when(
                                  data: (events) => CalendarMonthGridView(
                                    focusedMonth: focusedMonth,
                                    selectedDay: selectedDay,
                                    events: events,
                                    startDayOfWeek: settings.calendarStartDay,
                                  ),
                                  loading: () => const Center(
                                      child: AppLoadingIndicator()),
                                  error: (err, _) => Center(
                                      child:
                                          Text('Error loading events: $err')),
                                ),
                        ),
                      ),
                    ),
                  ],
                )
              : calendarView == CalendarView.weekTimeline ||
                      calendarView == CalendarView.fourDaysTimeline ||
                      calendarView == CalendarView.threeDaysTimeline
                  ? Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.surface
                            .withValues(alpha: palette.isAmoled ? 1.0 : 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: palette.text.withValues(alpha: 0.1),
                            width: 1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: monthEventsAsync.hasValue
                            ? CalendarMultiDayTimelineView(
                                selectedDay: selectedDay,
                                events: monthEventsAsync.value!,
                                daysCount:
                                    calendarView == CalendarView.weekTimeline
                                        ? 7
                                        : calendarView ==
                                                CalendarView.fourDaysTimeline
                                            ? 4
                                            : 3,
                                startDayOfWeek: settings.calendarStartDay,
                              )
                            : monthEventsAsync.when(
                                data: (events) => CalendarMultiDayTimelineView(
                                  selectedDay: selectedDay,
                                  events: events,
                                  daysCount:
                                      calendarView == CalendarView.weekTimeline
                                          ? 7
                                          : calendarView ==
                                                  CalendarView.fourDaysTimeline
                                              ? 4
                                              : 3,
                                  startDayOfWeek: settings.calendarStartDay,
                                ),
                                loading: () =>
                                    const Center(child: AppLoadingIndicator()),
                                error: (err, _) => Center(
                                    child: Text('Error loading events: $err')),
                              ),
                      ),
                    )
                  : calendarView == CalendarView.dailyTimeline
                      ? Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: palette.surface.withValues(
                                alpha: palette.isAmoled ? 1.0 : 0.5),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                                color: palette.text.withValues(alpha: 0.1),
                                width: 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: monthEventsAsync.hasValue
                                ? CalendarDailyTimelineView(
                                    selectedDay: selectedDay,
                                    events: monthEventsAsync.value!,
                                  )
                                : monthEventsAsync.when(
                                    data: (events) => CalendarDailyTimelineView(
                                      selectedDay: selectedDay,
                                      events: events,
                                    ),
                                    loading: () => const Center(
                                        child: AppLoadingIndicator()),
                                    error: (err, _) => Center(
                                        child:
                                            Text('Error loading events: $err')),
                                  ),
                          ),
                        )
                      : Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: palette.surface.withValues(
                                    alpha: palette.isAmoled ? 1.0 : 0.5),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: palette.text.withValues(alpha: 0.1),
                                    width: 1),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: TableCalendar<CalendarEvent>(
                                    firstDay: DateTime.utc(2015, 1, 1),
                                    lastDay: DateTime.utc(2035, 12, 31),
                                    focusedDay: focusedMonth,
                                    calendarFormat: calendarFormat,
                                    availableCalendarFormats: const {
                                      CalendarFormat.month: 'Month',
                                      CalendarFormat.twoWeeks: '2 Weeks',
                                      CalendarFormat.week: 'Week',
                                    },
                                    startingDayOfWeek:
                                        _startingDay(settings.calendarStartDay),
                                    selectedDayPredicate: (day) =>
                                        isSameDay(day, selectedDay),
                                    eventLoader: (day) =>
                                        ref.read(dayEventsProvider(day)),
                                    onDaySelected: (selected, focused) {
                                      ref
                                          .read(selectedDayProvider.notifier)
                                          .setDay(DateTime(
                                            selected.year,
                                            selected.month,
                                            selected.day,
                                          ));
                                      final normalizedFocused = DateTime(
                                        focused.year,
                                        focused.month,
                                        1,
                                      );
                                      if (normalizedFocused != focusedMonth) {
                                        ref
                                            .read(focusedMonthProvider.notifier)
                                            .setMonth(normalizedFocused);
                                      }
                                    },
                                    onPageChanged: (focused) {
                                      ref
                                          .read(focusedMonthProvider.notifier)
                                          .setMonth(DateTime(
                                            focused.year,
                                            focused.month,
                                            1,
                                          ));
                                    },
                                    onFormatChanged: (format) {
                                      if (calendarFormat != format) {
                                        ref
                                            .read(
                                                calendarFormatProvider.notifier)
                                            .setFormat(format);
                                      }
                                    },
                                    calendarStyle: CalendarStyle(
                                      markerDecoration: BoxDecoration(
                                          color: palette.primary,
                                          shape: BoxShape.circle),
                                      selectedDecoration: BoxDecoration(
                                          color: palette.primary,
                                          shape: BoxShape.circle),
                                      todayDecoration: BoxDecoration(
                                          color: palette.primary
                                              .withValues(alpha: 0.3),
                                          shape: BoxShape.circle),
                                      defaultTextStyle:
                                          TextStyle(color: palette.text),
                                      weekendTextStyle: TextStyle(
                                          color: palette.text
                                              .withValues(alpha: 0.6)),
                                      outsideTextStyle: TextStyle(
                                          color: palette.text
                                              .withValues(alpha: 0.3)),
                                    ),
                                    headerStyle: HeaderStyle(
                                      titleTextStyle: TextStyle(
                                          color: palette.text,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                      formatButtonTextStyle: TextStyle(
                                          color: palette.background,
                                          fontSize: 12),
                                      formatButtonDecoration: BoxDecoration(
                                        color: palette.text,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      leftChevronIcon: Icon(Icons.chevron_left,
                                          color: palette.text),
                                      rightChevronIcon: Icon(
                                          Icons.chevron_right,
                                          color: palette.text),
                                    ),
                                    daysOfWeekStyle: DaysOfWeekStyle(
                                      weekdayStyle: TextStyle(
                                          color: palette.text
                                              .withValues(alpha: 0.7)),
                                      weekendStyle: TextStyle(
                                          color: palette.text
                                              .withValues(alpha: 0.5)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: CalendarDayAgenda(
                                day: selectedDay,
                                monthEventsAsync: monthEventsAsync,
                                palette: palette,
                              ),
                            ),
                          ],
                        ),
        ),
      ),
    );
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  static StartingDayOfWeek _startingDay(int isoDay) {
    return switch (isoDay) {
      1 => StartingDayOfWeek.monday,
      2 => StartingDayOfWeek.tuesday,
      3 => StartingDayOfWeek.wednesday,
      4 => StartingDayOfWeek.thursday,
      5 => StartingDayOfWeek.friday,
      6 => StartingDayOfWeek.saturday,
      _ => StartingDayOfWeek.sunday,
    };
  }
}

