// Alarm settings: exact-alarm permission, test alarm, battery guidance,
// missed alarms. Web/desktop show the unavailable banner.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/alarm_providers.dart';
import '../data/alarm_scheduler.dart';

class AlarmSettingsScreen extends ConsumerWidget {
  const AlarmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarms')),
        body: const Center(
          child: Text(
            'System notifications only while the app is running. Configure sound paths per OS.',
          ),
        ),
      );
    }
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarms')),
        body: const Center(
          child: Text(
            'Alarms are unavailable on web. Export ICS as a workaround.',
          ),
        ),
      );
    }
    final missedAsync = ref.watch(_missedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Alarms')),
      body: ListView(
        children: [
          FutureBuilder<bool>(
            future: AlarmScheduler.canScheduleExact(),
            builder: (ctx, snap) {
              final ok = snap.data ?? false;
              return ListTile(
                title: const Text('Exact alarm permission'),
                subtitle: Text(ok ? 'Granted' : 'Not granted'),
                trailing: ok
                    ? null
                    : FilledButton(
                        onPressed: () =>
                            AlarmScheduler.openExactAlarmSettings(),
                        child: const Text('Grant'),
                      ),
              );
            },
          ),
          ListTile(
            title: const Text('Test alarm'),
            subtitle: const Text('Rings in 10 seconds'),
            onTap: () {
              AlarmScheduler.testAlarm();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Test alarm set')));
            },
          ),
          ListTile(
            title: const Text('Battery optimization'),
            subtitle: const Text(
              'Xiaomi, Samsung, Huawei and Oppo may block alarms. Open system settings.',
            ),
            onTap: () => AlarmScheduler.openBatterySettings(),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Missed alarms'),
          ),
          missedAsync.maybeWhen(
            data: (missed) => Column(
              children: [
                if (missed.isEmpty) const ListTile(title: Text('None')),
                for (final m in missed)
                  ListTile(
                    title: Text(m.sourceId),
                    subtitle: Text(
                      DateTime.fromMillisecondsSinceEpoch(
                        m.fireAtUtc,
                      ).toString(),
                    ),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

final _missedProvider = StreamProvider(
  (ref) => ref.watch(alarmRepositoryProvider).watchMissed(),
);
