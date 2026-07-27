import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_engine_provider.dart';
import '../../features/calendar/application/calendar_providers.dart';
import '../../features/quick_add/presentation/unified_creation_sheet.dart';
import 'nav_section.dart';

class KeyboardAttachedFabLocation extends FloatingActionButtonLocation {
  const KeyboardAttachedFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double fabX = (scaffoldGeometry.scaffoldSize.width -
            scaffoldGeometry.floatingActionButtonSize.width) /
        2.0;
    final double fabY = scaffoldGeometry.scaffoldSize.height -
        scaffoldGeometry.floatingActionButtonSize.height -
        88.0;
    return Offset(fabX, fabY);
  }
}

class QuickAddPill extends ConsumerWidget {
  final NavSection currentSection;
  const QuickAddPill({super.key, required this.currentSection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeEngineProvider);
    final selectedDay = ref.watch(selectedDayProvider);

    String getPillText() {
      if (currentSection == NavSection.calendar) {
        final monthStr = [
          '',
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ][selectedDay.month];
        return 'Add on $monthStr ${selectedDay.day}';
      }
      return 'Add ${currentSection.label}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48.0),
      child: Material(
        color: palette.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(32),
        elevation: 6,
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: () {
            showUnifiedCreationSheet(context, currentSection: currentSection);
          },
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: palette.text.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  getPillText(),
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.8),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Icon(
                  Icons.add,
                  color: palette.text.withValues(alpha: 0.8),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
