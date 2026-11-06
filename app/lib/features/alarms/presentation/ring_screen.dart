// Ring screen: cannot be dismissed with back; Snooze, Dismiss, or a
// context action is required. Auto-snoozes after 30 s of no interaction.
import 'dart:async';

// drift query extensions.
// ignore: unused_import
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/db_provider.dart';
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

  String _baseSourceId(String sourceId) {
    final at = sourceId.indexOf('@');
    if (at >= 0) return sourceId.substring(0, at);
    final hash = sourceId.indexOf('#');
    return hash >= 0 ? sourceId.substring(0, hash) : sourceId;
  }

  Future<bool> _isNumericHabit(String? sourceType, String? sourceId) async {
    if (sourceType == null || sourceId == null) return false;
    if (sourceType != 'habit' && sourceType != 'habit_reminder') return false;
    final db = ref.read(appDatabaseProvider);
    final habit = await (db.select(
      db.habits,
    )..where((h) => h.id.equals(_baseSourceId(sourceId)))).getSingleOrNull();
    return (habit?.goalAmount ?? 0) > 0;
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
              final isHabit =
                  alarm?.sourceType == 'habit' ||
                  alarm?.sourceType == 'habit_reminder';
              return FutureBuilder<bool>(
                future: _isNumericHabit(alarm?.sourceType, alarm?.sourceId),
                builder: (ctx, numSnap) {
                  final numeric = isHabit && (numSnap.data ?? false);
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
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        alarm?.title ?? 'Alarm',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (long)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Repeats every minute until resolved.',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              final code = alarm?.requestCode;
                              if (code != null) {
                                await ref
                                    .read(alarmRepositoryProvider)
                                    .snoozeRequest(code);
                              }
                              if (context.mounted) context.pop();
                            },
                            child: const Text('Snooze'),
                          ),
                          if (numeric)
                            FilledButton(
                              onPressed: () async {
                                final code = alarm?.requestCode;
                                if (code != null) {
                                  await ref
                                      .read(alarmRepositoryProvider)
                                      .completeHabitPlusOne(code);
                                }
                                if (context.mounted) context.pop();
                              },
                              child: const Text('+1'),
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
                          TextButton(
                            onPressed: () async {
                              final code = alarm?.requestCode;
                              if (code != null) {
                                await ref
                                    .read(alarmRepositoryProvider)
                                    .dismissRequest(code);
                              }
                              if (context.mounted) context.pop();
                            },
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text(
                          'Open item',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
