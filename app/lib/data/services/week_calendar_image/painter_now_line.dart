part of '../week_calendar_image.dart';

extension _WeekCalendarPainterNowLine on _WeekCalendarPainter {
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
}
