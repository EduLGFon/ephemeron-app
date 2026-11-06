part of '../tasks_screen.dart';

extension on TasksScreen {
  Future<void> _select(WidgetRef ref, String? id) async {
    ref.read(selectedTaskListProvider.notifier).select(id);
    ref.read(selectedSmartListProvider.notifier).select(null);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSelectedTaskListId(id);
    } catch (_) {}
  }

  Future<void> _selectSmart(WidgetRef ref, String id) async {
    ref.read(selectedSmartListProvider.notifier).select(id);
    ref.read(selectedTaskListProvider.notifier).select(null);
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setSelectedTaskListId(null);
    } catch (_) {}
  }

  Future<void> _smartActions(
    BuildContext context,
    WidgetRef ref,
    SmartList smart,
  ) async {
    final action = await showModalBottomSheet<_SmartAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit smart list'),
              onTap: () => Navigator.of(ctx).pop(_SmartAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete smart list'),
              onTap: () => Navigator.of(ctx).pop(_SmartAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == _SmartAction.edit) {
      await showSmartListEditor(context, smartList: smart);
      return;
    }
    await ref.read(taskRepositoryProvider).deleteSmartList(smart.id);
    if (ref.read(selectedSmartListProvider) == smart.id) {
      ref.read(selectedSmartListProvider.notifier).select(null);
    }
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _rescheduleAll(
    BuildContext context,
    WidgetRef ref,
    List<Task> overdue,
  ) async {
    final repo = ref.read(taskRepositoryProvider);
    final today = _today();
    var count = 0;
    for (final t in overdue) {
      final list = t.listId == null
          ? null
          : ref.read(taskListsByIdProvider)[t.listId];
      if (isMicrosoftTask(
        taskMicrosoftAccount: t.microsoftAccount,
        listMicrosoftAccount: list?.microsoftAccount,
      )) {
        continue;
      }
      await repo.updateTask(t.id, dueDate: () => today);
      count++;
    }
    if (count == 0) return;
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rescheduled $count tasks')));
    }
  }

  void _showCompleted(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _CompletedScreen()));
  }
}
