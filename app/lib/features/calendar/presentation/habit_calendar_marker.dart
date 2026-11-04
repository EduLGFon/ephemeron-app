// Compact habit marker for calendar surfaces: name plus done/skipped icon.
// Tap toggles done for the day; long-press opens skip/open actions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/habits/habit_calendar_entry.dart';
import '../../habits/application/habits_providers.dart';

class HabitCalendarMarker extends ConsumerWidget {
  const HabitCalendarMarker({
    super.key,
    required this.entry,
    this.compact = false,
  });

  final HabitCalendarEntry entry;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      onTap: () => ref
          .read(habitRepositoryProvider)
          .toggleHabitDone(entry.habitId, entry.dayKey),
      onLongPress: () => _showActions(context, ref),
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

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                entry.skipped ? Icons.check_rounded : Icons.remove_rounded,
              ),
              title: Text(entry.skipped ? 'Unskip' : 'Skip'),
              onTap: () {
                ref
                    .read(habitRepositoryProvider)
                    .setSkipped(entry.habitId, entry.dayKey, !entry.skipped);
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open habits'),
              onTap: () {
                final router = GoRouter.maybeOf(context);
                Navigator.of(ctx).pop();
                router?.go('/tab3');
              },
            ),
          ],
        ),
      ),
    );
  }
}
