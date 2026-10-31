// Alarm settings: exact-alarm permission, per-preset test buttons,
// battery guidance, upcoming + missed alarms. Web/desktop show the
// simulation note instead of the unavailable banner.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/alarms/alarm_preset.dart';
import '../application/alarm_providers.dart';
import '../data/alarm_scheduler.dart';

class AlarmSettingsScreen extends ConsumerWidget {
  const AlarmSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarms')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Web simulation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Browsers cannot fire alarms in the background. While this tab '
              'is open, reminders arrive as snackbars and full-screen alarms '
              'arrive as pop-up dialogs with sound. Keep the tab open for '
              'timely alerts, or export ICS to your system calendar.',
            ),
            const SizedBox(height: 12),
            _PresetCards(ref),
            const SizedBox(height: 12),
            _Upcoming(ref),
            _Missed(ref),
          ],
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarms')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Desktop simulation. System notifications plus in-app pop-up '
              'alarms while the app is running. Configure sound paths per OS.',
            ),
            const SizedBox(height: 12),
            _PresetCards(ref),
            const SizedBox(height: 12),
            _Upcoming(ref),
            _Missed(ref),
          ],
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarms')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'iOS allows at most 64 pending notifications; the app keeps the '
              'same rolling window capped at 60. No full-screen ring screen '
              'is possible on iOS: alerts arrive as time-sensitive '
              'notifications.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Critical Alerts ring through silent mode and need Apple '
              'approval for the App Store build.',
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final ok = await AlarmScheduler.requestCriticalAlerts();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Critical Alerts granted.'
                            : 'Critical Alerts not granted. The native '
                                  'request needs an Xcode build with the '
                                  'entitlement (see docs/TODO.md).',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Request Critical Alerts'),
            ),
          ],
        ),
      );
    }
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Three alarm styles. Reminders (early/at-time notifications) '
              'always fire separately and are set per item.',
            ),
          ),
          for (final p in AlarmPreset.values)
            ListTile(
              leading: Icon(
                p == AlarmPreset.notification
                    ? Icons.notifications_outlined
                    : p == AlarmPreset.fullScreenShort
                    ? Icons.fullscreen
                    : Icons.alarm_on,
              ),
              title: Text(p.title),
              subtitle: Text(p.description),
              trailing: TextButton(
                onPressed: () {
                  AlarmScheduler.testAlarm(p);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Test ${p.title.toLowerCase()} set (10 s)'),
                    ),
                  );
                },
                child: const Text('Test'),
              ),
            ),
          ListTile(
            title: const Text('Battery optimization'),
            subtitle: const Text(
              'Xiaomi, Samsung, Huawei and Oppo may block alarms. Open system settings.',
            ),
            onTap: () => AlarmScheduler.openBatterySettings(),
          ),
          const Divider(),
          _Upcoming(ref),
          _Missed(ref),
        ],
      ),
    );
  }
}

class _PresetCards extends StatelessWidget {
  const _PresetCards(this.ref);
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final p in AlarmPreset.values)
          Card(
            child: ListTile(
              title: Text(p.title),
              subtitle: Text(p.description),
            ),
          ),
      ],
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming(this.ref);
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef innerRef) {
    final upcoming = ref.watch(upcomingAlarmsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.all(16), child: Text('Upcoming')),
        upcoming.maybeWhen(
          data: (list) => Column(
            children: [
              if (list.isEmpty) const ListTile(title: Text('None scheduled')),
              for (final a in list.take(20))
                ListTile(
                  title: Text(a.title ?? a.sourceId),
                  subtitle: Text(
                    '${a.kind} - ${a.preset ?? ''} - '
                    '${DateTime.fromMillisecondsSinceEpoch(a.fireAtUtc)}',
                  ),
                ),
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Missed extends ConsumerWidget {
  const _Missed(this.ref);
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef innerRef) {
    final missedAsync = ref.watch(missedAlarmsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  title: Text(m.title ?? m.sourceId),
                  subtitle: Text(
                    DateTime.fromMillisecondsSinceEpoch(m.fireAtUtc).toString(),
                  ),
                ),
            ],
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
