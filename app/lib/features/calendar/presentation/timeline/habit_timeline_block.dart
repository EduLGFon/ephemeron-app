// Timed habit bubble on the hourly grid. Uses the same lane placement as
// events, keeps a fixed 30 minute height, and opens the habit action sheet.
import 'package:flutter/material.dart';

import '../../../../domain/habits/habit_calendar_entry.dart';
import '../habit_progress.dart';
import 'timeline_layout.dart';
import 'timeline_utils.dart';

class HabitTimelineBlock extends StatelessWidget {
  const HabitTimelineBlock({
    super.key,
    required this.entry,
    required this.dayIndex,
    required this.columnWidth,
    required this.hourHeight,
    required this.placement,
    required this.onTap,
  });

  final HabitCalendarEntry entry;
  final int dayIndex;
  final double columnWidth;
  final double hourHeight;
  final TimelinePlacement? placement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startMin = (entry.timeMinutes ?? 0).clamp(0, 1440).toDouble();
    final endMin = (startMin + timelineHabitBlockMinutes).clamp(0.0, 1440.0);
    final y0 = startMin / 60 * hourHeight;
    var height = (endMin - startMin) / 60 * hourHeight;
    if (height < 20) height = 20;

    final laneW = columnWidth - 4;
    final fracLeft = placement?.left ?? 0.0;
    final fracWidth = placement?.width ?? 1.0;
    final left = dayIndex * columnWidth + 2 + fracLeft * laneW;
    var width = fracWidth * laneW - 2;
    if (width < 14) width = 14;
    final nested = (placement?.depth ?? 0) > 0;

    final done = entry.done;
    final skipped = entry.skipped;
    final icon = done
        ? Icons.check_rounded
        : (skipped ? Icons.remove_rounded : Icons.radio_button_unchecked);
    final color = done
        ? scheme.primary
        : (skipped ? scheme.onSurfaceVariant : scheme.secondary);
    final progress = entry.hasGoal
        ? habitProgressText(entry.amount, entry.goalAmount!, unit: entry.unit)
        : null;

    return Positioned(
      left: left,
      top: y0,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: done
                ? color.withValues(alpha: 0.20)
                : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: color.withValues(alpha: nested ? 0.8 : 0.45),
              width: nested ? 1 : 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (width >= 26) ...[
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: entry.habitName,
                    children: [
                      if (progress != null && width >= 40)
                        TextSpan(
                          text: '  $progress',
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurface,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
