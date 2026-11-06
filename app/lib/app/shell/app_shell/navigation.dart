part of '../app_shell.dart';

extension _AppShellNavigation on _AppShellState {
  Future<void> _onTabSelected(int branchIndex) async {
    widget.navigationShell.goBranch(branchIndex);
    if (branchIndex == AppSection.calendar.index) {
      ref.read(timelineNowControllerProvider).refresh();
    }
    try {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.setLastTabIndex(branchIndex);
      await repo.setLastRoute('/tab$branchIndex');
    } catch (_) {}
  }

  void _showMore(BuildContext context, List<int> more, List<int> order) {
    showAppSheet<void>(
      context,
      builder: (ctx) => EscapeToClose(
        child: MoreSheet(
          more: more,
          onSelected: (idx) {
            Navigator.of(ctx).pop();
            _onTabSelected(idx);
          },
          onReorder: () async {
            Navigator.of(ctx).pop();
            await _reorderSheet(context, order);
          },
        ),
      ),
    );
  }

  Future<void> _reorderSheet(BuildContext context, List<int> order) async {
    final current = List<int>.from(order);
    await showAppSheet<void>(
      context,
      builder: (ctx) => EscapeToClose(
        child: StatefulBuilder(
          builder: (ctx, setSt) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Reorder sections',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                  ),
                  Flexible(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      onReorderItem: (oldIndex, newIndex) {
                        setSt(() {
                          final item = current.removeAt(oldIndex);
                          current.insert(newIndex, item);
                        });
                      },
                      children: [
                        for (final idx in current)
                          ListTile(
                            key: ValueKey(idx),
                            leading: Icon(AppSection.values[idx].icon),
                            title: Text(AppSection.values[idx].title),
                            trailing: const Icon(Icons.drag_handle),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: () async {
                        final repo = await ref.read(
                          settingsRepositoryProvider.future,
                        );
                        await repo.setNavOrder(current);
                        ref.invalidate(settingsRepositoryProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
