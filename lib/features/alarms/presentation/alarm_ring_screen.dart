import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/alarm_scheduler_provider.dart';
import '../domain/alarm_payload.dart';

/// Shown full-screen when a medium-preset alarm genuinely fires (device
/// locked/screen-off) — see AlarmScheduler's foreground response handler
/// for how this gets pushed. Auto-snoozes after 30 seconds of no
/// interaction, matching the brainstorm's "the full screen alarm
/// snoozes itself in 5min about 30s after start ringing" behavior.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({required this.payload, super.key});

  final AlarmPayload payload;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  static const _autoSnoozeAfter = Duration(seconds: 30);

  Timer? _autoSnoozeTimer;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _autoSnoozeTimer = Timer(_autoSnoozeAfter, _autoSnooze);
  }

  @override
  void dispose() {
    _autoSnoozeTimer?.cancel();
    super.dispose();
  }

  void _autoSnooze() {
    if (_resolved) return;
    _resolve(() => ref.read(alarmSchedulerProvider).snooze(widget.payload));
  }

  void _onSnoozePressed() {
    _resolve(() => ref.read(alarmSchedulerProvider).snooze(widget.payload));
  }

  void _onDonePressed() {
    _resolve(() => ref.read(alarmSchedulerProvider).markDone(widget.payload));
  }

  /// Guards against both the timer and a button tap firing (or two rapid
  /// taps) resolving this screen twice, and always cancels the pending
  /// timer once any resolution happens.
  void _resolve(Future<void> Function() action) {
    if (_resolved) return;
    _resolved = true;
    _autoSnoozeTimer?.cancel();
    action();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Swiping back shouldn't silently dismiss a ringing alarm — it
      // must be resolved via Snooze or Done, same as a real alarm clock.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.petrol,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alarm, size: 64, color: AppColors.amber),
                const SizedBox(height: 16),
                Text(
                  widget.payload.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontWeight: FontWeight.w600,
                    fontSize: 28,
                    color: Colors.white,
                  ),
                ),
                if (widget.payload.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.payload.body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
                const SizedBox(height: 48),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _onSnoozePressed,
                        child: const Text('Snooze 5 min'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.amber,
                          foregroundColor: AppColors.textLight,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _onDonePressed,
                        child: const Text('Mark done'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Auto-snoozing if left untouched...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
