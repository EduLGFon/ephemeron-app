import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/theme_palettes.dart';
import '../application/calendar_providers.dart';
import '../../sync/application/sync_service.dart';
import '../../settings/presentation/settings_screen.dart';

class CalendarAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const CalendarAppBar({
    super.key,
    required this.palette,
    required this.syncState,
    required this.titleColor,
  });

  final AppPalette palette;
  final SyncState syncState;
  final Color titleColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: GestureDetector(
        onTap: () {
          ref.read(syncServiceProvider.notifier).sync();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Calendar',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (syncState.isSyncing) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: titleColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        PopupMenuButton<CalendarView>(
          tooltip: 'Change view',
          icon: Icon(Icons.view_module, color: palette.primary),
          onSelected: (view) =>
              ref.read(calendarViewProvider.notifier).setView(view),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: CalendarView.monthGrid,
              child: Text('Month Grid View'),
            ),
            const PopupMenuItem(
              value: CalendarView.weekTimeline,
              child: Text('Week View'),
            ),
            const PopupMenuItem(
              value: CalendarView.fourDaysTimeline,
              child: Text('4 Days View'),
            ),
            const PopupMenuItem(
              value: CalendarView.threeDaysTimeline,
              child: Text('3 Days View'),
            ),
            const PopupMenuItem(
              value: CalendarView.dailyTimeline,
              child: Text('Daily Timeline'),
            ),
            const PopupMenuItem(
              value: CalendarView.compact,
              child: Text('Compact picker'),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Today',
          icon: Icon(Icons.today_outlined, color: palette.primary),
          onPressed: () {
            final now = DateTime.now();
            ref.read(selectedDayProvider.notifier).setDay(now);
            ref
                .read(focusedMonthProvider.notifier)
                .setMonth(DateTime(now.year, now.month, 1));
          },
        ),
        IconButton(
          tooltip: 'Manage Device Calendars',
          icon: Icon(Icons.calendar_month_outlined, color: palette.primary),
          onPressed: () {
            SettingsScreen.showDeviceCalendarsSheet(context, ref);
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
