// Month grid: custom painter, occurrence dots, tap to select day.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/time.dart';
import '../../../data/drift/app_database.dart';
import '../application/calendar_providers.dart';

class MonthView extends ConsumerWidget {
  const MonthView({super.key, required this.onDayTap});

  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(calendarStateProvider);
    final occAsync = ref.watch(windowOccurrencesProvider(window));
    final anchor = window.anchor;
    final first = DateTime(anchor.year, anchor.month, 1);
    final lead = (first.weekday - DateTime.monday + 7) % 7;
    final start = first.subtract(Duration(days: lead));
    final counts = <String, int>{};
    for (final o in occAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <OccurrenceCacheData>[],
    )) {
      counts[o.dayKey] = (counts[o.dayKey] ?? 0) + 1;
    }
    return Column(
      children: [
        _WeekdayHeader(),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: 42,
            itemBuilder: (ctx, i) {
              final day = start.add(Duration(days: i));
              final key = dateKey(day);
              final inMonth = day.month == anchor.month;
              final isToday = _isToday(day);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onDayTap(day),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _DayPainter(
                      inMonth: inMonth,
                      isToday: isToday,
                      selected: _isSameDay(day, window.anchor),
                      count: counts[key] ?? 0,
                      primary: Theme.of(context).colorScheme.primary,
                      onSurface: Theme.of(context).colorScheme.onSurface,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        semanticsLabel:
                            '${_monthName(day.month)} ${day.day}, ${counts[key] ?? 0} events',
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int m) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][m];
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (final n in names)
          Expanded(
            child: Center(
              child: Text(n, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ],
    );
  }
}

class _DayPainter extends CustomPainter {
  _DayPainter({
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.count,
    required this.primary,
    required this.onSurface,
  });

  final bool inMonth;
  final bool isToday;
  final bool selected;
  final int count;
  final Color primary;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = primary.withValues(alpha: 0.15),
      );
    }
    if (isToday) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        14,
        Paint()..color = primary.withValues(alpha: 0.3),
      );
    }
    final dots = count > 3 ? 3 : count;
    for (var i = 0; i < dots; i++) {
      canvas.drawCircle(
        Offset(size.width / 2 + (i - (dots - 1) / 2) * 8, size.height - 8),
        2.5,
        Paint()..color = inMonth ? primary : onSurface.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_DayPainter old) =>
      old.count != count ||
      old.selected != selected ||
      old.isToday != isToday ||
      old.inMonth != inMonth;
}
