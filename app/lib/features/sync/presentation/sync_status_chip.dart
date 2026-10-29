// Sync status chip: Synced / Syncing / Offline (pending N) / Error.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_providers.dart';
import '../../sync/data/sync_engine.dart';

class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    return switch (status) {
      SyncStatus.synced => const Chip(label: Text('Synced')),
      SyncStatus.syncing => const Chip(label: Text('Syncing')),
      SyncStatus.offline => const Chip(label: Text('Offline')),
      SyncStatus.error => ActionChip(
        label: const Text('Error'),
        onPressed: () => ref.read(syncStatusProvider.notifier).syncNow(),
      ),
    };
  }
}
