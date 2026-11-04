// Renders small PNGs for image-capable home-screen widgets (month grid,
// week calendar, habit heatmap, weekly focus chart) via home_widget's
// renderFlutterWidget.
// Foreground only: rendering needs a Flutter engine, so headless sync skips
// images and pushes text payloads instead.
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'home_widget_support.dart';
import 'week_calendar_data.dart';
import 'week_calendar_image.dart';
import 'week_widget_options.dart';

/// Month grid with event dots. Pure widget, no app dependencies.
class MonthGridImage extends StatelessWidget {
  const MonthGridImage({
    super.key,
    required this.year,
    required this.month,
    required this.eventDays,
    required this.today,
  });
  final int year;
  final int month;
  final Set<int> eventDays;
  final int today;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    // Monday-first offset.
    final offset = (first.weekday - 1) % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < offset; i++) {
      cells.add(Container());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final isToday = d == today;
      final hasEvent = eventDays.contains(d);
      cells.add(
        Container(
          alignment: Alignment.center,
          decoration: isToday
              ? BoxDecoration(
                  border: Border.all(color: const Color(0xFF000000)),
                )
              : null,
          child: Text(
            hasEvent ? '$d.' : '$d',
            style: const TextStyle(fontSize: 9),
          ),
        ),
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(
        Row(
          children: [
            for (var j = i; j < i + 7 && j < cells.length; j++)
              Expanded(child: cells[j]),
          ],
        ),
      );
    }
    return Container(
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.all(4),
      child: Column(children: rows),
    );
  }
}

/// 12-week heatmap of done days.
class HeatmapImage extends StatelessWidget {
  const HeatmapImage({super.key, required this.done, required this.end});
  final Set<String> done;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final start = DateTime(
      end.year,
      end.month,
      end.day,
    ).subtract(const Duration(days: 83));
    String key(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Container(
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var w = 0; w < 12; w++)
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  // Fixed cell height: renderFlutterWidget can lay this out
                  // with unbounded height, where Expanded would throw.
                  final cellH = cons.maxHeight.isFinite
                      ? (cons.maxHeight / 7) - 2
                      : 14.0;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var d = 0; d < 7; d++)
                        SizedBox(
                          height: cellH,
                          width: double.infinity,
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            color:
                                done.contains(
                                  key(start.add(Duration(days: w * 7 + d))),
                                )
                                ? const Color(0xFF000000)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 7 bars of minutes.
class WeekBarsImage extends StatelessWidget {
  const WeekBarsImage({super.key, required this.minutes});
  final List<int> minutes;

  @override
  Widget build(BuildContext context) {
    final max = minutes.fold<int>(1, (a, b) => b > a ? b : a);
    return Container(
      color: const Color(0xFFFFFFFF),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (ctx, cons) {
          // Bounded bar area: FractionallySizedBox needs a finite height,
          // which offscreen renders do not always provide.
          final areaH = cons.maxHeight.isFinite ? cons.maxHeight : 112.0;
          return SizedBox(
            height: areaH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in minutes)
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (m / max).clamp(0.05, 1.0),
                      child: Container(color: const Color(0xFF000000)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class WidgetImageService {
  /// Minimum interval between renders of the same image (15 min).
  static const int minRenderIntervalMs = 15 * 60 * 1000;

  /// Pure throttle check, unit-testable.
  static bool shouldRender({required int? lastMs, required int nowMs}) {
    if (lastMs == null) return true;
    return nowMs - lastMs >= minRenderIntervalMs;
  }

  /// Renders and stores the month grid; returns the saved path or null.
  /// Returns null without touching the platform channel on platforms
  /// without a widget host (renderFlutterWidget fires an unawaited
  /// saveWidgetData that would otherwise escape as an unhandled error).
  Future<String?> renderMonthGrid({
    required int year,
    required int month,
    required Set<int> eventDays,
    required int today,
  }) async {
    if (!isHomeWidgetSupported) return null;
    try {
      final path = await HomeWidget.renderFlutterWidget(
        MonthGridImage(
          year: year,
          month: month,
          eventDays: eventDays,
          today: today,
        ),
        key: 'month_calendar_image',
        logicalSize: const Size(360, 360),
        pixelRatio: 2,
      );
      return path as String?;
    } catch (_) {
      return null;
    }
  }

  /// Renders the current week grid at a wide 2:1 aspect ratio that fills a
  /// 4x2 widget cell area. 720x360 px at pixelRatio 2 keeps the Binder
  /// transaction small.
  Future<String?> renderWeekCalendar({
    required List<WeekCalendarDay> days,
    required DateTime now,
    WeekWidgetTheme theme = WeekWidgetTheme.light,
  }) async {
    if (!isHomeWidgetSupported) return null;
    try {
      final path = await HomeWidget.renderFlutterWidget(
        WeekCalendarImage(days: days, now: now, theme: theme),
        key: 'week_calendar_image',
        logicalSize: const Size(720, 360),
        pixelRatio: 1,
      );
      return path as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> renderHeatmap({
    required Set<String> done,
    required DateTime end,
  }) async {
    if (!isHomeWidgetSupported) return null;
    try {
      final path = await HomeWidget.renderFlutterWidget(
        HeatmapImage(done: done, end: end),
        key: 'habit_heatmap_image',
        logicalSize: const Size(360, 120),
        pixelRatio: 2,
      );
      return path as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String?> renderWeekBars({required List<int> minutes}) async {
    if (!isHomeWidgetSupported) return null;
    try {
      final path = await HomeWidget.renderFlutterWidget(
        WeekBarsImage(minutes: minutes),
        key: 'weekly_chart_image',
        logicalSize: const Size(360, 120),
        pixelRatio: 2,
      );
      return path as String?;
    } catch (_) {
      return null;
    }
  }
}
