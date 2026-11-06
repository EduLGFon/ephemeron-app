part of 'focus_screen.dart';

Future<void> _creditHabit(
  BuildContext context,
  WidgetRef ref,
  String habitId,
  int kept,
) async {
  final repo = ref.read(habitRepositoryProvider);
  final today = habitDateKey(DateTime.now());
  await repo.logDone(habitId, today);
  ref.invalidate(habitStreakProvider(habitId));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Credited $kept min to habit.'),
      duration: const Duration(seconds: 6),
      persist: false,
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          repo.backfill(habitId, today, 0, false);
          ref.invalidate(habitStreakProvider(habitId));
        },
      ),
    ),
  );
}

Future<String?> _askNote(BuildContext context) async {
  // Not disposed: disposal would race the dialog pop transition, which
  // rebuilds the text field for a few frames after pop.
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Session note (optional)'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(labelText: 'Note'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

String _formatElapsed(int elapsedMs) {
  final totalSec = (elapsedMs < 0 ? 0 : elapsedMs) ~/ 1000;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '${h.toString().padLeft(2, '0')}:$mm:$ss' : '$mm:$ss';
}

String _formatMin(int min) {
  if (min < 60) return '$min min';
  return '${min ~/ 60}h ${min % 60}m';
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});

  final List<int> days;

  @override
  Widget build(BuildContext context) {
    final max = days.fold<int>(1, (a, b) => b > a ? b : a);
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Container(
                      height: 60 * (days[i] / max),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    Text(
                      '${days[i]}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.fromMillisecondsSinceEpoch(
      session.startUtc,
      isUtc: true,
    ).toLocal();
    final end = session.endUtc == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            session.endUtc!,
            isUtc: true,
          ).toLocal();
    final min = end == null
        ? null
        : ((session.endUtc! - session.startUtc) / msPerMinute).floor();
    return ListTile(
      dense: true,
      title: Text(
        '${session.phase ?? 'focus'} - ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
        '${min == null ? '' : ' - ${_formatMin(min)}'}',
      ),
      subtitle: session.note == null || session.note!.isEmpty
          ? null
          : Text(session.note!),
    );
  }
}
