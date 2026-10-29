// Ring screen: cannot be dismissed with back; Snooze or Done required.
// Auto-snoozes after 30 s of no interaction.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/alarm_providers.dart';

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
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.alarm, size: 96, color: Colors.white),
                  const SizedBox(height: 24),
                  Text(
                    alarm?.sourceId ?? 'Alarm',
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  const SizedBox(height: 48),
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
