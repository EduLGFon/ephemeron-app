// Smart-list manager: saved views with live result counts, edit and delete.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/dialogs.dart';
import '../../../core/ui/empty_state.dart';
import '../../../data/drift/app_database.dart';
import '../application/tasks_providers.dart';
import 'smart_list_editor_sheet.dart';

class SmartListsScreen extends ConsumerWidget {
  const SmartListsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smartLists = ref.watch(smartListsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart lists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New smart list',
            onPressed: () => showSmartListEditor(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'smartListsFab',
        onPressed: () => showSmartListEditor(context),
        child: const Icon(Icons.add),
      ),
      body: smartLists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            const Center(child: Text('Could not load smart lists.')),
        data: (lists) {
          if (lists.isEmpty) {
            return EmptyState(
              icon: Icons.filter_alt_outlined,
              title: 'No smart lists',
              subtitle: 'Save a filter to reuse it from the Tasks screen.',
              actionLabel: 'Create smart list',
              onAction: () => showSmartListEditor(context),
            );
          }
          return RepaintBoundary(
            child: ListView.separated(
              itemCount: lists.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _SmartListTile(smartList: lists[index]),
            ),
          );
        },
      ),
    );
  }
}

class _SmartListTile extends ConsumerWidget {
  const _SmartListTile({required this.smartList});

  final SmartList smartList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(smartListTasksProvider(smartList));
    final count = results.maybeWhen(
      data: (tasks) => tasks.length,
      orElse: () => null,
    );
    return ListTile(
      leading: const Icon(Icons.filter_alt_outlined),
      title: Text(smartList.name),
      subtitle: Text(
        [
          smartFilterSummary(smartList),
          count == null
              ? 'Counting...'
              : (count == 1 ? '1 task' : '$count tasks'),
        ].join(' - '),
      ),
      onTap: () => showSmartListEditor(context, smartList: smartList),
      trailing: PopupMenuButton<_SmartAction>(
        tooltip: 'Smart list actions',
        onSelected: (action) => _onAction(context, ref, action),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _SmartAction.edit, child: Text('Edit')),
          PopupMenuItem(value: _SmartAction.delete, child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _SmartAction action,
  ) async {
    switch (action) {
      case _SmartAction.edit:
        await showSmartListEditor(context, smartList: smartList);
      case _SmartAction.delete:
        final ok = await showConfirmDialog(
          context,
          title: 'Delete "${smartList.name}"?',
          message:
              'The saved filter is removed. Tasks themselves are not '
              'changed.',
          confirmLabel: 'Delete',
        );
        if (!ok) return;
        await ref.read(taskRepositoryProvider).deleteSmartList(smartList.id);
        if (ref.read(selectedSmartListProvider) == smartList.id) {
          ref.read(selectedSmartListProvider.notifier).select(null);
        }
    }
  }
}

enum _SmartAction { edit, delete }
