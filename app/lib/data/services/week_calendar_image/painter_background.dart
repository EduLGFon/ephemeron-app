part of '../week_calendar_image.dart';

extension _WeekCalendarPainterBackground on _WeekCalendarPainter {
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
                ? _WeekCalendarPainter._todayShade
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
}
