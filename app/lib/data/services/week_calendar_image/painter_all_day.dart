part of '../week_calendar_image.dart';

extension _WeekCalendarPainterAllDay on _WeekCalendarPainter {
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
}
