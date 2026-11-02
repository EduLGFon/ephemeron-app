// Timeline background painters: day grid and current-time line.
import 'package:flutter/material.dart';

class TimelineGridPainter extends CustomPainter {
  TimelineGridPainter({
    required this.anchor,
    required this.dayCount,
    required this.hourHeight,
    required this.primary,
  });

  final DateTime anchor;
  final int dayCount;
  final double hourHeight;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / dayCount;
    final grid = Paint()..color = primary.withValues(alpha: 0.12);
    for (var h = 0; h <= 24; h++) {
      canvas.drawLine(
        Offset(0, h * hourHeight),
        Offset(size.width, h * hourHeight),
        grid,
      );
    }
    for (var i = 0; i <= dayCount; i++) {
      canvas.drawLine(
        Offset(i * colW, 0),
        Offset(i * colW, 24 * hourHeight),
        grid,
      );
    }
  }

  @override
  bool shouldRepaint(TimelineGridPainter old) =>
      old.anchor != anchor ||
      old.dayCount != dayCount ||
      old.hourHeight != hourHeight;
}

class TimelineNowLinePainter extends CustomPainter {
  TimelineNowLinePainter({
    required this.anchor,
    required this.dayCount,
    required this.hourHeight,
    required this.now,
  });

  final DateTime anchor;
  final int dayCount;
  final double hourHeight;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final colW = size.width / dayCount;
    for (var i = 0; i < dayCount; i++) {
      final day = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
      ).add(Duration(days: i));
      if (day.year == now.year &&
          day.month == now.month &&
          day.day == now.day) {
        final y = (now.hour * 60 + now.minute) / 60 * hourHeight;
        canvas.drawLine(
          Offset(i * colW, y),
          Offset((i + 1) * colW, y),
          Paint()
            ..color = Colors.red
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(TimelineNowLinePainter old) =>
      old.anchor != anchor ||
      old.dayCount != dayCount ||
      old.hourHeight != hourHeight ||
      old.now != now;
}
