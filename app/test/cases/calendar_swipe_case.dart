// Calendar horizontal swiping: drags snap to one period, short or vertical
// drags do not navigate, and month shifts stay inside the target month.
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/calendar_swipe.dart';
import 'package:ephemeron/features/calendar/presentation/timeline/timeline_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> _pump(WidgetTester tester, {bool enabled = true}) async {
  final shifts = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CalendarSwipe(
          enabled: enabled,
          onShift: shifts.add,
          child: const Center(child: Text('day')),
        ),
      ),
    ),
  );
  return shifts;
}

void main() {
  testWidgets('swiping left advances one period', (tester) async {
    final shifts = await _pump(tester);
    await tester.timedDrag(
      find.byType(CalendarSwipe),
      const Offset(-300, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shifts, [1]);
  });

  testWidgets('swiping right goes back one period', (tester) async {
    final shifts = await _pump(tester);
    await tester.timedDrag(
      find.byType(CalendarSwipe),
      const Offset(300, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shifts, [-1]);
  });

  testWidgets('short or vertical drags do not navigate', (tester) async {
    final shifts = await _pump(tester);
    await tester.timedDrag(
      find.byType(CalendarSwipe),
      const Offset(-40, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    await tester.timedDrag(
      find.byType(CalendarSwipe),
      const Offset(0, -300),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shifts, isEmpty);
  });

  testWidgets('disabled views ignore horizontal swipes', (tester) async {
    final shifts = await _pump(tester, enabled: false);
    await tester.timedDrag(
      find.byType(CalendarSwipe),
      const Offset(-300, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(shifts, isEmpty);
  });

  testWidgets('multi-day headers use each day\'s own weekday', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineDayHeader(
            anchor: DateTime(2027, 3, 1), // Monday
            dayCount: 4,
            gutterWidth: 48,
          ),
        ),
      ),
    );
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu'];
    for (var i = 0; i < weekdays.length; i++) {
      final dayNumber = '${i + 1}';
      final cell = find
          .ancestor(of: find.text(dayNumber), matching: find.byType(Column))
          .first;
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: cell, matching: find.byType(Text)),
          )
          .toList();
      expect(texts.first.data, weekdays[i]);
      expect(texts.last.data, dayNumber);
    }
  });

  test('month shift clamps the day and crosses years', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(calendarStateProvider.notifier);
    state.restore(CalendarViewKind.month, DateTime(2026, 1, 31));

    state.shiftMonths(1);
    expect(container.read(calendarStateProvider).anchor, DateTime(2026, 2, 28));

    state.shiftMonths(11);
    expect(container.read(calendarStateProvider).anchor, DateTime(2027, 1, 28));
  });
}
