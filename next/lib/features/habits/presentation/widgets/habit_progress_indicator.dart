import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/theme_palettes.dart';
import '../../application/habit_providers.dart';
import '../../domain/habit_metrics.dart';

class HabitProgressIndicator extends ConsumerWidget {
  const HabitProgressIndicator({
    super.key,
    required this.metrics,
    required this.palette,
  });

  final HabitMetrics metrics;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _StreakBadge(streak: metrics.currentStreak, color: palette.primary),
        const SizedBox(width: 12),
        ..._buildWeekStrip(metrics, ref),
      ],
    );
  }

  List<Widget> _buildWeekStrip(HabitMetrics metrics, WidgetRef ref) {
    final now = DateTime.now();
    return [
      for (int i = 0; i < metrics.last7Days.length; i++) ...[
        () {
          final status = metrics.last7Days[i];
          final day = now.subtract(Duration(days: 6 - i));
          const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
          final isCompleted = status == HabitDayStatus.completed;
          final isMissed = status == HabitDayStatus.missed;

          return GestureDetector(
            onTap: () {
              ref.read(habitSelectedDateProvider.notifier).state = day;
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekdays[day.weekday - 1],
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: palette.text.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (status) {
                        HabitDayStatus.completed => palette.primary,
                        HabitDayStatus.missed =>
                          Colors.redAccent.withValues(alpha: 0.6),
                        HabitDayStatus.notDue =>
                          palette.text.withValues(alpha: 0.1),
                        HabitDayStatus.future => Colors.transparent,
                      },
                      border: (status == HabitDayStatus.future ||
                              status == HabitDayStatus.notDue)
                          ? Border.all(
                              color: palette.text.withValues(alpha: 0.1))
                          : null,
                    ),
                    child: isCompleted
                        ? Icon(Icons.check, size: 8, color: palette.background)
                        : isMissed
                            ? Icon(Icons.close,
                                size: 8, color: palette.background)
                            : null,
                  ),
                ],
              ),
            ),
          );
        }(),
      ]
    ];
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak, required this.color});

  final int streak;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (streak == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
