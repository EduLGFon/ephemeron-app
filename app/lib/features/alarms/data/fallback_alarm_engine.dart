// In-app fallback for platforms without native alarms (web, desktop)
// and for foreground alerts. Polls alarms_index while the app runs and
// shows the closest matching UI: heads-up banner for reminders and the
// notification preset, full-screen dialog for full-screen presets.
// Sound uses SystemSound (no new dependencies); long preset repeats.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/alarms/alarm_preset.dart';
import '../application/alarm_providers.dart';

bool get isFallbackPlatform =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Plays a short beep. Long preset repeats via the caller loop.
Future<void> playAlarmBeep(AlarmPreset preset) async {
  try {
    if (preset == AlarmPreset.fullScreenLong) {
      await SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    } else {
      await SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
    }
  } catch (_) {
    // Sound is best-effort on web/desktop.
  }
}

/// Place once near the app shell. Checks due rows every 20 s and on
/// dependency change. Shows at most one dialog at a time.
class AlarmListener extends ConsumerStatefulWidget {
  const AlarmListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AlarmListener> createState() => _AlarmListenerState();
}

class _AlarmListenerState extends ConsumerState<AlarmListener>
    with WidgetsBindingObserver {
  Timer? _poll;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_showing || !mounted) return;
    final repo = ref.read(alarmRepositoryProvider);
    late final List<dynamic> due;
    try {
      due = await repo.dueAlarms();
    } catch (_) {
      return;
    }
    if (due.isEmpty || !mounted) return;
    final row = due.first;
    final kind = (row.kind ?? 'alarm') as String;
    final preset = AlarmPreset.tryParse(row.preset as String?);
    await repo.markFired(row.id as String);
    try {
      await playAlarmBeep(preset ?? AlarmPreset.notification);
    } catch (_) {}
    if (!mounted) return;
    final title = (row.title as String?) ?? 'Alarm';
    if (kind == 'reminder' ||
        preset == null ||
        preset == AlarmPreset.notification) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kind == 'reminder' ? 'Reminder: $title' : title),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Open', onPressed: () {}),
        ),
      );
      return;
    }
    _showing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FallbackRingDialog(
        title: title,
        preset: preset,
        requestCode: (row.requestCode as int?) ?? 0,
      ),
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FallbackRingDialog extends ConsumerStatefulWidget {
  const _FallbackRingDialog({
    required this.title,
    required this.preset,
    required this.requestCode,
  });

  final String title;
  final AlarmPreset preset;
  final int requestCode;

  @override
  ConsumerState<_FallbackRingDialog> createState() =>
      _FallbackRingDialogState();
}

class _FallbackRingDialogState extends ConsumerState<_FallbackRingDialog> {
  Timer? _auto;
  Timer? _beepLoop;
  int _beeps = 0;

  @override
  void initState() {
    super.initState();
    _auto = Timer(const Duration(seconds: 30), () {
      if (mounted) Navigator.of(context).pop();
    });
    if (widget.preset == AlarmPreset.fullScreenLong) {
      _beepLoop = Timer.periodic(const Duration(seconds: 5), (_) async {
        _beeps++;
        if (_beeps > 6) {
          _beepLoop?.cancel();
          return;
        }
        await playAlarmBeep(widget.preset);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _beepLoop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final long = widget.preset == AlarmPreset.fullScreenLong;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              long ? Icons.alarm_on : Icons.alarm,
              color: long ? Colors.red : null,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title)),
          ],
        ),
        content: Text(
          long
              ? 'Full-screen alert with constant sound and vibration. '
                    'On phones this arrives as a notification while in use.'
              : 'Full-screen alert with short sound. '
                    'On phones this arrives as a notification while in use.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref
                  .read(alarmRepositoryProvider)
                  .snoozeRequest(widget.requestCode);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Snooze 10 min'),
          ),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(alarmRepositoryProvider)
                  .markDone(widget.requestCode);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
