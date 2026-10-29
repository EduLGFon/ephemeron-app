// Failed changes: Retry and Discard per op.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_providers.dart';

class FailedChangesScreen extends ConsumerWidget {
  const FailedChangesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failedAsync = ref.watch(failedChangesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Failed changes')),
      body: failedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Could not load.')),
        data: (ops) {
          if (ops.isEmpty) {
            return const Center(child: Text('No failed changes'));
          }
          return ListView(
            children: [
              for (final op in ops)
                ListTile(
                  title: Text('${op.entity} ${op.op}'),
                  subtitle: Text(op.lastError ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () =>
                            ref.read(syncEngineProvider).retryFailed(op.id),
                        child: const Text('Retry'),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(syncEngineProvider).discardFailed(op.id),
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
