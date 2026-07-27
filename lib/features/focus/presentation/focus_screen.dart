import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_engine_provider.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/focus_metrics_providers.dart';
import '../application/focus_timer_controller.dart';
import '../application/focus_timer_state.dart';
import '../domain/focus_mode.dart';
import 'focus_month_screen.dart';
import 'widgets/focus_timer_display.dart';
import 'widgets/focus_control_buttons.dart';
import 'widgets/focus_link_selector.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watch parts of timerState that don't change every second
    final timerState = ref.watch(focusTimerControllerProvider.select((state) => 
        FocusTimerState(
          mode: state.mode,
          isRunning: state.isRunning,
          keepScreenOn: state.keepScreenOn,
          startedAt: state.startedAt,
          linkedTaskId: state.linkedTaskId,
          linkedHabitId: state.linkedHabitId,
          pomodoroPhase: state.pomodoroPhase,
        )));
    final controller = ref.read(focusTimerControllerProvider.notifier);
    final palette = ref.watch(themeEngineProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('Focus',
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                  minWidth: constraints.maxWidth,
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    child: Column(
                      children: [
                        SegmentedButton<FocusMode>(
                          style: SegmentedButton.styleFrom(
                            backgroundColor:
                                palette.surface.withValues(alpha: 0.5),
                            foregroundColor: palette.text,
                            selectedBackgroundColor:
                                palette.primary.withValues(alpha: 0.2),
                            selectedForegroundColor: palette.primary,
                          ),
                          segments: const [
                            ButtonSegment(
                                value: FocusMode.pomodoro,
                                label: Text('Pomodoro')),
                            ButtonSegment(
                                value: FocusMode.stopwatch,
                                label: Text('Stopwatch')),
                          ],
                          selected: {timerState.mode},
                          onSelectionChanged: timerState.isRunning
                              ? null
                              : (selection) =>
                                  controller.setMode(selection.first),
                        ),

                        const Spacer(),

                        FocusTimerDisplay(
                          palette: palette,
                          timerState: timerState,
                        ),

                        const SizedBox(height: 48),

                        FocusLinkSelector(
                            state: timerState,
                            controller: controller,
                            palette: palette),

                        const SizedBox(height: 16),

                        // Compact Glassmorphic Toggle Button for Keep Screen On
                        InkWell(
                          onTap: () => controller
                              .setKeepScreenOn(!timerState.keepScreenOn),
                          borderRadius: BorderRadius.circular(20),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: timerState.keepScreenOn
                                  ? palette.primary.withValues(alpha: 0.15)
                                  : palette.surface.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: timerState.keepScreenOn
                                    ? palette.primary
                                    : palette.text.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  timerState.keepScreenOn
                                      ? Icons.wb_sunny
                                      : Icons.wb_sunny_outlined,
                                  size: 16,
                                  color: timerState.keepScreenOn
                                      ? palette.primary
                                      : palette.text.withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Keep screen on',
                                  style: TextStyle(
                                    color: timerState.keepScreenOn
                                        ? palette.primary
                                        : palette.text.withValues(alpha: 0.8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Spacer(),

                        FocusControlButtons(
                            state: timerState,
                            controller: controller,
                            palette: palette),

                        const SizedBox(height: 24),

                        _TotalsRow(palette: palette),
                        const SizedBox(
                            height: 90), // Bottom padding for floating pill
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TotalsRow extends ConsumerWidget {
  const _TotalsRow({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(totalFocusedTodayProvider);
    final week = ref.watch(totalFocusedThisWeekProvider);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FocusMonthScreen()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.primary.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 18, color: palette.primary),
            const SizedBox(width: 8),
            Text(
              'Today: ${_short(today.value)}  ·  This week: ${_short(week.value)}',
              style:
                  TextStyle(color: palette.text, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  String _short(Duration? d) {
    if (d == null) return '...';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }
}
