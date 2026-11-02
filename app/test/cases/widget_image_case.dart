// Widget images must lay out under unbounded height (offscreen renders
// for home-screen widgets do not always provide finite constraints).
import 'package:ephemeron/data/services/widget_image_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpUnbounded(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(child: child),
    ),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('heatmap lays out with unbounded height', (
    WidgetTester tester,
  ) async {
    await _pumpUnbounded(
      tester,
      HeatmapImage(done: const {}, end: DateTime(2026, 11, 2)),
    );
  });

  testWidgets('week bars lay out with unbounded height', (
    WidgetTester tester,
  ) async {
    await _pumpUnbounded(
      tester,
      const WeekBarsImage(minutes: [10, 20, 30, 40, 50, 60, 70]),
    );
  });

  testWidgets('month grid lays out with unbounded height', (
    WidgetTester tester,
  ) async {
    await _pumpUnbounded(
      tester,
      const MonthGridImage(year: 2026, month: 11, eventDays: {2}, today: 2),
    );
  });
}
