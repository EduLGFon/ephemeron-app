part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderCalendar on HomeWidgetDataBinder {
  Future<void> _refreshEvents() async {
    try {
      final repo = ref.read(occurrenceRepositoryProvider);
      final now = DateTime.now();
      final key =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final occs = await repo.watchDay(key).first;
      final titles = occs.take(5).map((o) => o.title).toList();
      await _svc.updateCollection(
        keyPrefix: 'day_agenda_collection',
        provider: 'DayAgendaCollectionProvider',
        title: 'Today',
        items: occs
            .take(5)
            .map((o) => {'id': o.id, 'title': o.title})
            .toList()
            .cast<Map<String, String>>(),
      );
      _mark('day_agenda_collection');
      await _svc.updateByPrefix(
        keyPrefix: 'next_events',
        title: titles.isEmpty ? 'No events' : titles.first,
        body: titles.length > 1 ? titles.skip(1).join('\n') : '',
      );
      _mark('next_events');
    } catch (_) {}
  }

  /// Week payload shared by the text push and the image renderer.
  /// Honors the persisted week-widget options: [WeekWidgetOptions.dayCount]
  /// columns starting at the persisted anchor (or the current week / today
  /// when no anchor is stored). The anchor survives restart and refresh.
  Future<
    ({
      DateTime start,
      List<WeekCalendarDay> days,
      String title,
      String body,
      String dayKeys,
      WeekWidgetTheme theme,
    })
  >
  _weekCalendarData() async {
    var firstDay = DateTime.monday;
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      firstDay = settings.weekStart;
    } catch (_) {}
    final options = await WeekWidgetOptions.load();
    final dayCount = WeekWidgetOptions.sanitizeDayCount(options.dayCount);
    final now = DateTime.now();
    DateTime start;
    final anchor = options.anchorDayKey == null
        ? null
        : WeekWidgetOptions.tryParseDayKey(options.anchorDayKey!);
    if (anchor != null) {
      start = anchor;
    } else if (dayCount == 7) {
      start = weekStartFor(now, weekStartDay: firstDay);
    } else {
      final today = DateTime(now.year, now.month, now.day);
      start = today;
    }
    final end = start.add(Duration(days: dayCount));
    final occs = await ref
        .read(occurrenceRepositoryProvider)
        .watchWindow(start, end)
        .first;
    final days = buildWeekCalendar(
      occurrences: occs,
      weekStart: start,
      dayCount: dayCount,
    );
    return (
      start: start,
      days: days,
      title: weekCalendarTitle(start, dayCount: dayCount),
      body: weekCalendarBody(days),
      dayKeys: days.map((d) => dateKey(d.date)).join(','),
      theme: options.theme,
    );
  }

  Future<void> _refreshWeekCalendar() async {
    try {
      final data = await _weekCalendarData();
      await _svc.update(
        keyPrefix: 'week_calendar',
        provider: 'WeekCalendarWidgetProvider',
        title: data.title,
        body: data.body,
        extra: {'days': data.dayKeys, 'theme': data.theme.key},
      );
      _mark('week_calendar');
    } catch (_) {}
  }

  /// Re-renders the week widget immediately, bypassing the 15-minute
  /// throttle. Used after the user taps previous/next so the new range
  /// appears right away. The native provider cannot re-render the Flutter
  /// image by itself; this foreground re-render is the documented path.
  Future<void> refreshWeekCalendarNow({bool skipThrottle = true}) async {
    try {
      if (skipThrottle) {
        // Best-effort: still record the render time for the throttle.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
            'widget_image_last_week_calendar',
            DateTime.now().millisecondsSinceEpoch,
          );
        } catch (_) {}
      }
      final data = await _weekCalendarData();
      final path = await WidgetImageService().renderWeekCalendar(
        days: data.days,
        now: DateTime.now(),
        theme: data.theme,
      );
      if (path != null) {
        await _svc.update(
          keyPrefix: 'week_calendar',
          provider: 'WeekCalendarWidgetProvider',
          title: data.title,
          body: data.body,
          imagePath: path,
          extra: {'days': data.dayKeys, 'theme': data.theme.key},
        );
      }
    } catch (_) {}
  }

  /// Shifts the persisted week-widget anchor by one visible span and
  /// re-renders the widget foreground. Returns the new anchor start.
  Future<DateTime> shiftWeekWidgetAnchor(int direction) async {
    final options = await WeekWidgetOptions.load();
    final dayCount = WeekWidgetOptions.sanitizeDayCount(options.dayCount);
    var firstDay = DateTime.monday;
    try {
      final settings = await ref.read(settingsRepositoryProvider.future);
      firstDay = settings.weekStart;
    } catch (_) {}
    final now = DateTime.now();
    final current =
        (options.anchorDayKey == null
            ? null
            : WeekWidgetOptions.tryParseDayKey(options.anchorDayKey!)) ??
        (dayCount == 7
            ? weekStartFor(now, weekStartDay: firstDay)
            : DateTime(now.year, now.month, now.day));
    final shifted = WeekWidgetOptions.shiftAnchor(current, dayCount, direction);
    await options
        .copyWith(anchorDayKey: () => WeekWidgetOptions.dayKey(shifted))
        .save();
    await refreshWeekCalendarNow();
    return shifted;
  }

  /// Clears the persisted anchor so the widget shows the current week.
  Future<void> resetWeekWidgetAnchor() async {
    final options = await WeekWidgetOptions.load();
    await options.copyWith(anchorDayKey: () => null).save();
    await refreshWeekCalendarNow();
  }
}
