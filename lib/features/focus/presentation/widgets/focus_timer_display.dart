import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/theme_palettes.dart';
import '../../application/focus_timer_controller.dart';
import '../../application/focus_timer_state.dart';
import '../../domain/focus_mode.dart';

class FocusTimerDisplay extends ConsumerWidget {
  const FocusTimerDisplay({
    super.key,
    required this.palette,
    required this.timerState,
  });

  final AppPalette palette;
  final FocusTimerState timerState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final elapsedNotifier = ref.watch(focusElapsedProvider);

    return Container(
      width: 280,
      height: 280,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surface.withValues(alpha: palette.isAmoled ? 1.0 : 0.8),
        boxShadow: [
          BoxShadow(
            color: palette.primary
                .withValues(alpha: timerState.isRunning ? 0.3 : 0.05),
            blurRadius: timerState.isRunning ? 40 : 20,
            spreadRadius: timerState.isRunning ? 10 : 0,
          )
        ],
        border: Border.all(
          color: palette.primary
              .withValues(alpha: timerState.isRunning ? 0.5 : 0.1),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: elapsedNotifier,
                    builder: (context, elapsed, _) {
                      return Text(
                        _formatDuration(elapsed),
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 80,
                          fontWeight: FontWeight.w600,
                          color: palette.text,
                          height: 1.0,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (timerState.mode == FocusMode.pomodoro)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'of ${_formatDuration(timerState.pomodoroTarget)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: palette.text.withValues(alpha: 0.6)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
