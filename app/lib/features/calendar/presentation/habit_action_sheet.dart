// Shared habit action sheet for calendar markers and timed habit blocks.
// Shows the habit name, day, goal progress, and the log actions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/device_date_format.dart';
import '../../../core/ui/app_sheet.dart';
import '../../../core/ui/escape_to_close.dart';
import '../../../data/drift/app_database.dart';
import '../../../domain/habits/date_key.dart';
import '../../../domain/habits/habit_calendar_entry.dart';
import '../../habits/application/habits_providers.dart';
import 'habit_progress.dart';

Future<void> showHabitActionSheet(
  BuildContext context,
  HabitCalendarEntry entry,
) {
  return showAppSheet<void>(
    context,
    builder: (_) => EscapeToClose(child: HabitActionSheet(entry: entry)),
  );
}

class HabitActionSheet extends ConsumerWidget {
  const HabitActionSheet({super.key, required this.entry});

  final HabitCalendarEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref
        .watch(habitLogsProvider(entry.habitId))
        .maybeWhen(data: (v) => v, orElse: () => const <HabitLog>[]);
    final log = _logFor(logs, entry.dayKey);
    final done = log?.done ?? entry.done;
    final skipped = log?.skipped ?? entry.skipped;
    final amount = log?.amount ?? entry.amount;
    final goal = (entry.goalAmount ?? 0) > 0 ? entry.goalAmount! : null;
    final step = entry.increment ?? 1;
    final repo = ref.read(habitRepositoryProvider);

    final date = DeviceDateFormat.date(context, parseKey(entry.dayKey));
    final time = entry.timeMinutes == null
        ? null
        : TimeOfDay(
            hour: entry.timeMinutes! ~/ 60,
            minute: entry.timeMinutes! % 60,
          ).format(context);
    final when = time == null ? date : '$date - $time';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.habitName,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(when, style: Theme.of(context).textTheme.bodySmall),
                if (goal != null) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (amount / goal).clamp(0.0, 1.0),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    habitProgressText(amount, goal, unit: entry.unit),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(done ? Icons.undo_rounded : Icons.check_rounded),
            title: Text(done ? 'Mark as not concluded' : 'Mark as concluded'),
            onTap: () => repo.setDone(entry.habitId, entry.dayKey, !done),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: Text(habitStepLabel(step, entry.unit)),
            subtitle: goal == null
                ? null
                : Text(habitProgressText(amount, goal, unit: entry.unit)),
            onTap: () => repo.addAmount(entry.habitId, entry.dayKey, step),
          ),
          ListTile(
            leading: Icon(
              skipped ? Icons.play_arrow_rounded : Icons.pause_rounded,
            ),
            title: Text(skipped ? 'Unskip for today' : 'Skip for today'),
            onTap: () => repo.setSkipped(entry.habitId, entry.dayKey, !skipped),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text('Open habits'),
            onTap: () {
              final router = GoRouter.maybeOf(context);
              Navigator.of(context).pop();
              router?.go('/tab3');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

HabitLog? _logFor(List<HabitLog> logs, String dayKey) {
  for (final log in logs) {
    if (log.dayKey == dayKey) return log;
  }
  return null;
}
