// Week time-grid image for the home-screen week calendar widget.
// Draws day columns with an all-day band and 24-hour event blocks.
// The widget is rendered offscreen at a fixed logical size and then scaled
// by the launcher, so this must lay out with unbounded constraints.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'week_calendar_data.dart';
import 'week_widget_options.dart';

part 'week_calendar_image/placed_item.dart';
part 'week_calendar_image/palette.dart';
part 'week_calendar_image/painter.dart';
part 'week_calendar_image/painter_background.dart';
part 'week_calendar_image/painter_headers.dart';
part 'week_calendar_image/painter_all_day.dart';
part 'week_calendar_image/painter_timed.dart';
part 'week_calendar_image/painter_now_line.dart';
part 'week_calendar_image/painter_helpers.dart';

class WeekCalendarImage extends StatelessWidget {
  const WeekCalendarImage({
    super.key,
    required this.days,
    required this.now,
    this.theme = WeekWidgetTheme.light,
    this.logicalSize = const Size(720, 360),
  });

  final List<WeekCalendarDay> days;
  final DateTime now;
  final WeekWidgetTheme theme;

  /// Full render size used when the offscreen host leaves an axis
  /// unbounded. `renderFlutterWidget` sizes the canvas from `logicalSize`
  /// but can hand the widget an unbounded height; using a smaller fallback
  /// there centers a 180 px band inside a 360 px PNG.
  final Size logicalSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme == WeekWidgetTheme.transparent
          ? const Color(0x00000000)
          : null,
      child: LayoutBuilder(
        builder: (ctx, cons) {
          final width = cons.maxWidth.isFinite
              ? cons.maxWidth.clamp(1.0, 4096.0)
              : logicalSize.width;
          final height = cons.maxHeight.isFinite
              ? cons.maxHeight.clamp(1.0, 4096.0)
              : logicalSize.height;
          return SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _WeekCalendarPainter(days: days, now: now, theme: theme),
            ),
          );
        },
      ),
    );
  }
}
