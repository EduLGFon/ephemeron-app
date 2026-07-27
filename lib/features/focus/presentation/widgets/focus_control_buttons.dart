import 'package:flutter/material.dart';

import '../../../../core/theme/theme_palettes.dart';
import '../../application/focus_timer_controller.dart';
import '../../application/focus_timer_state.dart';

class FocusControlButtons extends StatelessWidget {
  const FocusControlButtons({
    super.key,
    required this.state,
    required this.controller,
    required this.palette,
  });

  final FocusTimerState state;
  final FocusTimerController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final hasSession = state.startedAt != null;

    if (!hasSession) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: palette.background,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        onPressed: controller.start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.text,
            side: BorderSide(color: palette.text.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: () async {
            await controller.stop();
          },
          icon: const Icon(Icons.stop),
          label: const Text('Stop', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.background,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: state.isRunning ? controller.pause : controller.resume,
          icon: Icon(state.isRunning ? Icons.pause : Icons.play_arrow),
          label: Text(state.isRunning ? 'Pause' : 'Resume',
              style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
