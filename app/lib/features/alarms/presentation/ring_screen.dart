// Ring screen: cannot be dismissed with back; Snooze or Done required.
// Auto-snoozes after 30 s of no interaction. Preset-aware: long preset
// shows repeating-alert styling and custom snooze chips.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/alarms/alarm_preset.dart';
import '../application/alarm_providers.dart';
import 'alarm_preset_picker.dart';

class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({super.key});

  @override
  ConsumerState<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends ConsumerState<RingScreen> {
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer(const Duration(seconds: 30), () async {
      final repo = ref.read(alarmRepositoryProvider);
      final latest = await repo.latestFired();
      if (latest?.requestCode != null) {
        await repo.snoozeRequest(latest!.requestCode!);
      }
      if (mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: FutureBuilder(
            future: ref.read(alarmRepositoryProvider).latestFired(),
            builder: (ctx, snap) {
              final alarm = snap.data;
              final preset = AlarmPreset.tryParse(alarm?.preset);
              final long = preset == AlarmPreset.fullScreenLong;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    long ? Icons.alarm_on : Icons.alarm,
                    size: 96,
                    color: long ? Colors.redAccent : Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    preset?.title ?? 'Alarm',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alarm?.title ?? 'Alarm',
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                  if (long)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Repeats every minute until resolved.',
                        style: TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SnoozePicker(
                    onPick: (m) async {
                      final code = alarm?.requestCode;
                      if (code != null) {
                        await ref
                            .read(alarmRepositoryProvider)
                            .snoozeRequest(code, minutes: m);
                      }
                      if (context.mounted) context.pop();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FilledButton(
                        onPressed: () async {
                          final code = alarm?.requestCode;
                          if (code != null) {
                            await ref
                                .read(alarmRepositoryProvider)
                                .snoozeRequest(code);
                          }
                          if (context.mounted) context.pop();
                        },
                        child: const Text('Snooze 10 min'),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final code = alarm?.requestCode;
                          if (code != null) {
                            await ref
                                .read(alarmRepositoryProvider)
                                .markDone(code);
                          }
                          if (context.mounted) context.pop();
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text(
                      'Open item',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
