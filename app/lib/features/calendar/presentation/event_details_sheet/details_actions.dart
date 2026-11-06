part of '../event_details_sheet.dart';

Future<void> _delete(BuildContext context, WidgetRef ref, Event e) async {
  final recurring =
      e.rrule != null && e.rrule!.isNotEmpty && e.recurringMasterId == null;
  EditScope scope = EditScope.all;
  DateTime orig = DateTime.now().toUtc();
  if (recurring) {
    if (!context.mounted) return;
    final s = await showScopeSheet(context);
    if (s == null) return;
    scope = s;
    orig = DateTime.fromMillisecondsSinceEpoch(e.startUtc ?? 0, isUtc: true);
    if (!context.mounted) return;
    if (scope == EditScope.single || scope == EditScope.following) {
      final pending = ref.read(pendingOperationsProvider);
      final opId = await pending.scheduleEventDeleteOccurrence(
        e.id,
        orig,
        scope: scope,
      );
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Event deleted'),
            duration: const Duration(seconds: 6),
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => pending.cancel(opId),
            ),
          ),
        );
      }
      return;
    }
  }
  if (!context.mounted) return;
  final confirm =
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete event?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirm || !context.mounted) return;
  final pending = ref.read(pendingOperationsProvider);
  final opId = await pending.scheduleEventDelete(e.id);
  if (context.mounted) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Event deleted'),
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => pending.cancel(opId),
        ),
      ),
    );
  }
}
