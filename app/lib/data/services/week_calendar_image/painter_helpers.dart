part of '../week_calendar_image.dart';

extension _WeekCalendarPainterHelpers on _WeekCalendarPainter {
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

  Color _contrast(Color background) => background.computeLuminance() > 0.55
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekday(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - DateTime.monday) % 7];
  }

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
