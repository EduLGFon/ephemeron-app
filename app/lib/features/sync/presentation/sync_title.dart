// Tappable AppBar title that forces a Google sync. Primary color when a
// sync ran in the last 30 minutes, gray otherwise. Manual taps restart
// the auto-sync countdown.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/sync_providers.dart';
import '../data/sync_engine.dart';

class SyncTitle extends ConsumerStatefulWidget {
  const SyncTitle({super.key, required this.text});

  final String text;

  @override
  ConsumerState<SyncTitle> createState() => _SyncTitleState();
}

class _SyncTitleState extends ConsumerState<SyncTitle> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh the freshness color without waiting for provider changes.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lastSync = ref.watch(lastGoogleSyncAtProvider);
    final status = ref.watch(syncStatusProvider);
    final fresh =
        lastSync != null &&
        DateTime.now().toUtc().difference(lastSync) <
            const Duration(minutes: 30);
    final color = (fresh || status == SyncStatus.syncing)
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return InkWell(
      onTap: () =>
          ref.read(googleAutoSyncServiceProvider).syncNowAndReschedule(),
      child: Text(
        widget.text,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
      ),
    );
  }
}
