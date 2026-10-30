// Trash: restore, permanent delete, empty old items.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/tasks_providers.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashAsync = ref.watch(trashProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          TextButton(
            onPressed: () async {
              final n = await ref.read(taskRepositoryProvider).emptyTrash();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Purged $n old items')));
              }
            },
            child: const Text('Empty old'),
          ),
        ],
      ),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load trash.')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const Center(child: Text('Trash is empty'));
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, i) {
              final t = tasks[i];
              return Dismissible(
                key: ValueKey(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(
                    Icons.delete_forever,
                    color: Colors.white,
                  ),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete forever?'),
                          content: Text('"${t.title}" cannot be recovered.'),
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
                },
                onDismissed: (_) =>
                    ref.read(taskRepositoryProvider).purgeTask(t.id),
                child: ListTile(
                  title: Text(t.title),
                  trailing: IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () =>
                        ref.read(taskRepositoryProvider).restoreTasks([t.id]),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
