import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/app_settings_provider.dart';
import '../../../core/theme/theme_engine_provider.dart';
import '../../sync/application/sync_service.dart';
import 'settings_screen.dart';

class SettingsSyncSection extends ConsumerWidget {
  const SettingsSyncSection({super.key});

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final syncState = ref.watch(syncServiceProvider);
    final syncNotifier = ref.read(syncServiceProvider.notifier);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Auto Sync'),
          subtitle: const Text('Synchronize events and tasks in the background'),
          value: settings.autoSync,
          onChanged: notifier.setAutoSync,
        ),
        if (settings.autoSync)
          ListTile(
            title: const Text('Sync Interval'),
            subtitle: const Text('How often the app refreshes in background'),
            trailing: DropdownButton<int>(
              value: settings.syncIntervalMinutes,
              items: const [
                DropdownMenuItem(value: 15, child: Text('15 minutes')),
                DropdownMenuItem(value: 30, child: Text('30 minutes')),
                DropdownMenuItem(value: 60, child: Text('1 hour')),
                DropdownMenuItem(value: 120, child: Text('2 hours')),
              ],
              onChanged: (val) {
                if (val != null) notifier.setSyncIntervalMinutes(val);
              },
            ),
          ),
        ListTile(
          title: const Text('Manual Force Sync'),
          subtitle: syncState.lastSyncedAt != null
              ? Text('Last synced at ${_formatDateTime(syncState.lastSyncedAt!)}')
              : const Text('Never synced'),
          trailing: syncState.isSyncing
              ? const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.icon(
                  onPressed: () async {
                    await syncNotifier.sync();
                    final current = ref.read(syncServiceProvider);
                    if (current.error != null && context.mounted) {
                      final palette = ref.read(themeEngineProvider);
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: palette.surface,
                          surfaceTintColor: Colors.transparent,
                          title: const Text('Sync Error'),
                          content: Text(current.error!),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                SettingsScreen.showDevLogsDialog(context, ref);
                              },
                              child: const Text('View Logs'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Sync Now'),
                ),
        ),
        if (syncState.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Sync error: ${syncState.error}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
