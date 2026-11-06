part of '../week_calendar_image.dart';

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

  @override
  bool shouldRepaint(covariant _WeekCalendarPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.now != now ||
      oldDelegate.theme != theme;
}
