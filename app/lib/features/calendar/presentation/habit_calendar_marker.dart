// Compact habit marker for calendar surfaces: name plus done/skipped icon.
// Tap or long-press opens the shared habit action sheet.
import 'package:flutter/material.dart';

import '../../../domain/habits/habit_calendar_entry.dart';
import 'habit_action_sheet.dart';

class HabitCalendarMarker extends StatelessWidget {
  const HabitCalendarMarker({
    super.key,
    required this.entry,
    this.compact = false,
  });

  final HabitCalendarEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = entry.done;
    final skipped = entry.skipped;
    final icon = done
        ? Icons.check_rounded
        : (skipped ? Icons.remove_rounded : Icons.radio_button_unchecked);
    final color = done
        ? scheme.primary
        : (skipped ? scheme.onSurfaceVariant : scheme.secondary);
    return InkWell(
      onTap: () => showHabitActionSheet(context, entry),
      onLongPress: () => showHabitActionSheet(context, entry),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: compact ? 14 : 18,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 10 : 12, color: color),
            if (!compact) const SizedBox(width: 3),
            if (!compact)
              Expanded(
                child: Text(
                  entry.habitName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: compact ? 9 : 10,
                    color: scheme.onSurface,
                  ),
                ),
              )
            else
              Flexible(
                child: Text(
                  entry.habitName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: scheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
