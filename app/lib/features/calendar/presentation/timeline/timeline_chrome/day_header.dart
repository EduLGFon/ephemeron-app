part of '../timeline_chrome.dart';

class TimelineDayHeader extends StatelessWidget {
  const TimelineDayHeader({
    super.key,
    required this.anchor,
    required this.dayCount,
    required this.gutterWidth,
    this.swipeOffset = 0,
    this.onDayTap,
  });

  final DateTime anchor;
  final int dayCount;
  final double gutterWidth;
  final double swipeOffset;
  final void Function(DateTime day)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        SizedBox(width: gutterWidth),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) {
              final dayWidth = cons.maxWidth / dayCount;
              final stripCount = timelineStripCount(dayCount);
              final stripAnchor = timelineStripAnchor(anchor);
              return IntrinsicHeight(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: stripCount * dayWidth,
                    maxWidth: stripCount * dayWidth,
                    child: Transform.translate(
                      offset: Offset(
                        -timelineBufferDays * dayWidth + swipeOffset,
                        0,
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < stripCount; i++)
                            SizedBox(
                              width: dayWidth,
                              child: _dayCell(
                                context,
                                timelineDayStart(stripAnchor, i),
                                now,
                                onDayTap,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    DateTime now,
    void Function(DateTime day)? onDayTap,
  ) {
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DeviceDateFormat.weekday(context, day),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDayTap == null ? null : () => onDayTap(day),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: isToday
                  ? BoxDecoration(color: color.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${day.day}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isToday ? color.onPrimary : null,
                  fontWeight: isToday ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
