import 'package:flutter/material.dart';
import '../../../core/theme/theme_palettes.dart';
import 'quick_add_target.dart'; // Ensure it exists

class CreationTargetSwitcher extends StatelessWidget {
  final QuickAddTarget currentTarget;
  final ValueChanged<QuickAddTarget> onTargetChanged;
  final AppPalette palette;

  const CreationTargetSwitcher({
    super.key,
    required this.currentTarget,
    required this.onTargetChanged,
    required this.palette,
  });

  String _getTargetLabel(QuickAddTarget target) {
    switch (target) {
      case QuickAddTarget.event:
        return 'Event';
      case QuickAddTarget.task:
        return 'Task';
      case QuickAddTarget.habit:
        return 'Habit';
      case QuickAddTarget.note:
        return 'Note';
      case QuickAddTarget.countdown:
        return 'Countdown';
    }
  }

  IconData _getTargetIcon(QuickAddTarget target) {
    switch (target) {
      case QuickAddTarget.event:
        return Icons.event;
      case QuickAddTarget.task:
        return Icons.check_circle_outline;
      case QuickAddTarget.habit:
        return Icons.loop;
      case QuickAddTarget.note:
        return Icons.edit_note;
      case QuickAddTarget.countdown:
        return Icons.timer_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<QuickAddTarget>(
      color: palette.surface,
      offset: const Offset(0, 30),
      onSelected: onTargetChanged,
      itemBuilder: (context) => [
        for (final t in QuickAddTarget.values)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                Icon(_getTargetIcon(t), color: palette.text, size: 20),
                const SizedBox(width: 12),
                Text(_getTargetLabel(t), style: TextStyle(color: palette.text)),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getTargetLabel(currentTarget),
            style: TextStyle(
                color: palette.text,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, color: palette.text, size: 20),
        ],
      ),
    );
  }
}
