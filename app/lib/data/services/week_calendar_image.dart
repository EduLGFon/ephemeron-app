// Week time-grid image for the home-screen week calendar widget.
// Draws day columns with an all-day band and 24-hour event blocks.
// The widget is rendered offscreen at a fixed logical size and then scaled
// by the launcher, so this must lay out with unbounded constraints.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'week_calendar_data.dart';
import 'week_widget_options.dart';

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

class _PlacedItem {
  const _PlacedItem(this.item, this.left, this.width);
  final WeekCalendarItem item;
  final double left;
  final double width;
}

/// Resolved palette for one widget theme. Transparent paints no solid
/// background and uses light foreground colors so the grid stays readable
/// over launcher wallpaper.
class _WeekPalette {
  const _WeekPalette({
    required this.background,
    required this.line,
    required this.night,
    required this.text,
    required this.todayFill,
    required this.todayText,
    required this.nowLine,
  });

  final Color? background;
  final Color line;
  final Color night;
  final Color text;
  final Color todayFill;
  final Color todayText;
  final Color nowLine;

  static _WeekPalette of(WeekWidgetTheme theme) {
    switch (theme) {
      case WeekWidgetTheme.dark:
        return const _WeekPalette(
          background: Color(0xFF1B1B1D),
          line: Color(0xFF3A3A3E),
          night: Color(0xFF232326),
          text: Color(0xFFFFFFFF),
          todayFill: Color(0xFFFFFFFF),
          todayText: Color(0xFF000000),
          nowLine: Color(0xFFFF5252),
        );
      case WeekWidgetTheme.transparent:
        return const _WeekPalette(
          background: null,
          line: Color(0x99FFFFFF),
          night: Color(0x22000000),
          text: Color(0xFFFFFFFF),
          todayFill: Color(0xAAFFFFFF),
          todayText: Color(0xFF000000),
          nowLine: Color(0xFFFF5252),
        );
      case WeekWidgetTheme.light:
        return const _WeekPalette(
          background: Color(0xFFFFFFFF),
          line: Color(0xFFE2E2E2),
          night: Color(0xFFF7F7F7),
          text: Color(0xFF000000),
          todayFill: Color(0xFF000000),
          todayText: Color(0xFFFFFFFF),
          nowLine: Color(0xFFD50000),
        );
    }
  }
}

class _WeekCalendarPainter extends CustomPainter {
  _WeekCalendarPainter({
    required this.days,
    required this.now,
    this.theme = WeekWidgetTheme.light,
  });

  final List<WeekCalendarDay> days;
  final DateTime now;
  final WeekWidgetTheme theme;

  static const Color _todayShade = Color(0x14000000);

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty || size.width <= 0 || size.height <= 0) return;
    final palette = _WeekPalette.of(theme);
    if (palette.background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = palette.background!);
    }

    final colW = size.width / days.length;
    final headerH = (size.height * 0.11).clamp(8.0, 28.0);
    final maxAllDay = days.fold<int>(
      0,
      (m, d) => math.max(m, d.allDayItems.length),
    );
    final allDayRows = maxAllDay == 0
        ? 0
        : math.min(maxAllDay, size.height > 220 ? 3 : 2);
    final allDayRowH = allDayRows == 0
        ? 0.0
        : (size.height * 0.22 / allDayRows).clamp(4.0, 10.0);
    final allDayH = allDayRows == 0 ? 0.0 : allDayRowH * allDayRows + 2;
    final gridTop = headerH + allDayH;
    final gridH = math.max(1.0, size.height - gridTop);

    _paintBackground(canvas, size, colW, gridTop, gridH, palette);
    _paintHeaders(canvas, colW, headerH, palette);
    if (allDayRows > 0) {
      _paintAllDay(canvas, colW, headerH, allDayRowH, allDayRows, palette);
    }
    _paintTimed(canvas, colW, gridTop, gridH);
    _paintNowLine(canvas, colW, gridTop, gridH, palette);
  }

  void _paintBackground(
    Canvas canvas,
    Size size,
    double colW,
    double gridTop,
    double gridH,
    _WeekPalette palette,
  ) {
    for (var i = 0; i < days.length; i++) {
      final left = i * colW;
      if (_sameDay(days[i].date, now)) {
        canvas.drawRect(
          Rect.fromLTWH(left, 0, colW, size.height),
          Paint()
            ..color = theme == WeekWidgetTheme.light
                ? _todayShade
                : palette.todayFill.withValues(alpha: 0.18),
        );
      }
    }
    if (gridH > 12) {
      // Shade night hours so daytime events stand out at a glance.
      canvas.drawRect(
        Rect.fromLTWH(0, gridTop, size.width, gridH * 6 / 24),
        Paint()..color = palette.night,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, gridTop + gridH * 21 / 24, size.width, gridH * 3 / 24),
        Paint()..color = palette.night,
      );
      final linePaint = Paint()
        ..color = palette.line
        ..strokeWidth = 0.5;
      for (final hour in const [6, 12, 18]) {
        final y = gridTop + gridH * hour / 24;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
      }
    }
    final vertical = Paint()
      ..color = palette.line
      ..strokeWidth = 0.5;
    for (var i = 1; i < days.length; i++) {
      final x = i * colW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), vertical);
    }
  }

  void _paintHeaders(
    Canvas canvas,
    double colW,
    double headerH,
    _WeekPalette palette,
  ) {
    final weekdaySize = math.min(6.5, headerH * 0.36);
    final dateSize = math.min(9.0, headerH * 0.5);
    for (var i = 0; i < days.length; i++) {
      final day = days[i].date;
      final isToday = _sameDay(day, now);
      final left = i * colW;
      if (isToday) {
        canvas.drawRect(
          Rect.fromLTWH(left, 0, colW, headerH),
          Paint()..color = palette.todayFill,
        );
      }
      final color = isToday ? palette.todayText : palette.text;
      final label = _weekday(day.weekday);
      if (colW >= 20 && headerH >= 9) {
        _drawText(
          canvas,
          label,
          Offset(left, 0.5),
          colW,
          weekdaySize,
          color: color,
        );
        _drawText(
          canvas,
          '${day.day}',
          Offset(left, headerH * 0.45),
          colW,
          dateSize,
          color: color,
          weight: FontWeight.w600,
        );
      } else if (colW >= 4) {
        _drawText(
          canvas,
          '${day.day}',
          Offset(left, (headerH - dateSize) / 2),
          colW,
          dateSize,
          color: color,
          weight: FontWeight.w600,
        );
      }
    }
  }

  void _paintAllDay(
    Canvas canvas,
    double colW,
    double headerH,
    double rowH,
    int maxRows,
    _WeekPalette palette,
  ) {
    final uneven = days.any((d) => d.allDayItems.length > maxRows);
    final showRows = uneven ? math.max(0, maxRows - 1) : maxRows;
    for (var i = 0; i < days.length; i++) {
      final items = days[i].allDayItems;
      final left = i * colW;
      for (var r = 0; r < items.length && r < showRows; r++) {
        final rect = Rect.fromLTWH(
          left + 0.5,
          headerH + r * rowH + 1,
          math.max(0.8, colW - 1),
          math.max(1.5, rowH - 1),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          Paint()..color = items[r].color,
        );
        if (colW >= 14 && rowH >= 6) {
          _drawText(
            canvas,
            items[r].title,
            Offset(rect.left + 0.8, rect.top + 0.2),
            rect.width - 1.6,
            math.min(6.0, rowH * 0.72),
            color: _contrast(items[r].color),
          );
        }
      }
      if (items.length > showRows && colW >= 8 && rowH >= 5) {
        final extra = items.length - showRows;
        _drawText(
          canvas,
          '+$extra',
          Offset(left, headerH + showRows * rowH + 1),
          colW,
          math.min(6.0, rowH * 0.72),
          color: palette.text,
          weight: FontWeight.w600,
        );
      }
    }
  }

  void _paintTimed(Canvas canvas, double colW, double gridTop, double gridH) {
    for (var i = 0; i < days.length; i++) {
      final left = i * colW;
      for (final placed in _placeDay(days[i])) {
        final day = days[i].date;
        final startMin = _minutesIntoDay(placed.item.start, day);
        var endMin = _minutesIntoDay(placed.item.end, day);
        if (endMin <= startMin) endMin = math.min(1440.0, startMin + 15);
        final top = gridTop + startMin / 1440 * gridH;
        final bottom = gridTop + endMin / 1440 * gridH;
        final rect = Rect.fromLTWH(
          left + placed.left * colW + 0.5,
          top,
          math.max(0.8, placed.width * colW - 1),
          math.max(1.5, bottom - top),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          Paint()..color = placed.item.color,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          Paint()
            ..color = const Color(0x55FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.4,
        );
        if (rect.height >= 5 && rect.width >= 6) {
          final textColor = _contrast(placed.item.color);
          _drawText(
            canvas,
            placed.item.title,
            Offset(rect.left + 0.8, rect.top + 0.2),
            rect.width - 1.6,
            math.min(6.0, math.max(3.5, rect.height * 0.5)),
            color: textColor,
          );
          if (rect.height >= 13 && rect.width >= 26) {
            _drawText(
              canvas,
              _clock(placed.item.start),
              Offset(rect.left + 0.8, rect.top + rect.height * 0.5),
              rect.width - 1.6,
              math.min(5.5, math.max(3.5, rect.height * 0.32)),
              color: textColor.withValues(alpha: 0.9),
            );
          }
        }
      }
    }
  }

  void _paintNowLine(
    Canvas canvas,
    double colW,
    double gridTop,
    double gridH,
    _WeekPalette palette,
  ) {
    final index = days.indexWhere((d) => _sameDay(d.date, now));
    if (index < 0) return;
    final minutes = now.hour * 60 + now.minute;
    final y = gridTop + minutes / 1440 * gridH;
    canvas.drawLine(
      Offset(index * colW, y),
      Offset((index + 1) * colW, y),
      Paint()
        ..color = palette.nowLine
        ..strokeWidth = 0.9,
    );
  }

  List<_PlacedItem> _placeDay(WeekCalendarDay day) {
    final items = day.timedItems;
    if (items.isEmpty) return const [];
    final laneEnds = <DateTime>[];
    final lanes = <int>[];
    for (final item in items) {
      var lane = -1;
      for (var i = 0; i < laneEnds.length; i++) {
        if (!laneEnds[i].isAfter(item.start)) {
          lane = i;
          break;
        }
      }
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(item.end);
      } else {
        laneEnds[lane] = item.end;
      }
      lanes.add(lane);
    }
    final count = laneEnds.isEmpty ? 1 : laneEnds.length;
    return [
      for (var i = 0; i < items.length; i++)
        _PlacedItem(items[i], lanes[i] / count, 1 / count),
    ];
  }

  double _minutesIntoDay(DateTime t, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return t.difference(start).inMinutes.toDouble().clamp(0.0, 1440.0);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double maxWidth,
    double fontSize, {
    Color color = const Color(0xFF000000),
    FontWeight weight = FontWeight.w400,
  }) {
    if (maxWidth <= 0 || fontSize <= 0 || text.isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.0,
          color: color,
          fontWeight: weight,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, offset);
  }

  static Color _contrast(Color background) =>
      background.computeLuminance() > 0.55
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _weekday(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - DateTime.monday) % 7];
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _WeekCalendarPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.now != now ||
      oldDelegate.theme != theme;
}
