part of '../week_calendar_image.dart';

extension _WeekCalendarPainterTimed on _WeekCalendarPainter {
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
}
