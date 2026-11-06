part of '../home_widget_data_binder.dart';

extension HomeWidgetDataBinderImages on HomeWidgetDataBinder {
  /// Renders image widgets only when a matching widget is pinned (when the
  /// platform reports installed widgets) and at most every 15 minutes per
  /// image. Falls back to the throttle when the installed list is
  /// unavailable so images still refresh on platforms without the API.
  /// No-op on platforms without a widget host.
  Future<void> _refreshImages() async {
    if (!isHomeWidgetSupported) return;
    final images = WidgetImageService();
    Set<String>? installed;
    try {
      final all = await HomeWidget.getInstalledWidgets();
      installed = {for (final w in all) w.androidClassName ?? ''};
    } catch (_) {}
    bool want(String provider) {
      if (installed == null) return true;
      return installed.any((c) => widgetProviderMatches(c, provider));
    }

    Future<bool> due(String key) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getInt('widget_image_last_$key');
        final ok = WidgetImageService.shouldRender(
          lastMs: last,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
        if (ok) {
          await prefs.setInt(
            'widget_image_last_$key',
            DateTime.now().millisecondsSinceEpoch,
          );
        }
        return ok;
      } catch (_) {
        return true;
      }
    }

    if (want('WeekCalendarWidgetProvider') && await due('week_calendar')) {
      try {
        await refreshWeekCalendarNow(skipThrottle: false);
      } catch (_) {}
    }
    if (want('MonthCalendarWidgetProvider') && await due('month_calendar')) {
      try {
        final now = DateTime.now();
        final from = DateTime(now.year, now.month, 1);
        final to = DateTime(now.year, now.month + 1, 0);
        final occs = await ref
            .read(occurrenceRepositoryProvider)
            .watchWindow(from, to)
            .first;
        final days = <int>{};
        for (final o in occs) {
          final start = DateTime.fromMillisecondsSinceEpoch(o.startUtc);
          if (start.year == now.year && start.month == now.month) {
            days.add(start.day);
          }
        }
        final path = await images.renderMonthGrid(
          year: now.year,
          month: now.month,
          eventDays: days,
          today: now.day,
        );
        if (path != null) {
          await _svc.updateByPrefix(
            keyPrefix: 'month_calendar',
            title: 'Calendar',
            body: days.isEmpty ? 'No events.' : '${days.length} days',
            imagePath: path,
          );
        }
      } catch (_) {}
    }
    if (want('HabitHeatmapWidgetProvider') && await due('habit_heatmap')) {
      try {
        final repo = ref.read(habitRepositoryProvider);
        final habits = await repo.watchHabits(archived: false).first;
        final pinnedHeatId = await _config('HabitStreakWidgetProvider');
        final heatHabit = pinnedHeatId == null
            ? (habits.isEmpty ? null : habits.first)
            : (habits.any((h) => h.id == pinnedHeatId)
                  ? habits.firstWhere((h) => h.id == pinnedHeatId)
                  : (habits.isEmpty ? null : habits.first));
        if (heatHabit != null) {
          final logs = await repo.watchLogs(heatHabit.id).first;
          final done = {
            for (final l in logs)
              if (l.done) l.dayKey,
          };
          final path = await images.renderHeatmap(
            done: done,
            end: DateTime.now(),
          );
          if (path != null) {
            await _svc.updateByPrefix(
              keyPrefix: 'habit_heatmap',
              title: 'Heatmap',
              body: heatHabit.name,
              imagePath: path,
            );
          }
        }
      } catch (_) {}
    }
    if (want('WeeklyChartWidgetProvider') && await due('weekly_chart')) {
      try {
        final repo = ref.read(focusRepositoryProvider);
        final now = DateTime.now();
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        final minutes = <int>[];
        for (var i = 0; i < 7; i++) {
          final day = start.add(Duration(days: i));
          final next = day.add(const Duration(days: 1));
          minutes.add(
            await repo.totalMinutes(
              day.millisecondsSinceEpoch,
              next.millisecondsSinceEpoch,
            ),
          );
        }
        final path = await images.renderWeekBars(minutes: minutes);
        if (path != null) {
          await _svc.updateByPrefix(
            keyPrefix: 'weekly_chart',
            title: 'Week',
            body: 'Focus ${minutes.reduce((a, b) => a + b)} min',
            imagePath: path,
          );
        }
      } catch (_) {}
    }
  }
}
