part of '../week_calendar_image.dart';

extension _WeekCalendarPainterHeaders on _WeekCalendarPainter {
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
}
