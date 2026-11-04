// Calendar navigation: month double-tap opens the 7-day timeline centered on
// the tapped day; 7-day header day numbers open the single-day view.
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/month_view.dart';
import 'package:ephemeron/features/calendar/presentation/timeline/timeline_chrome.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

class _FixedWindow extends CalendarState {
  _FixedWindow(this.window);
  final CalendarWindow window;
  @override
  CalendarWindow build() => window;
}

Future<void> _pumpMonth(
  WidgetTester tester,
  AppDatabase db,
  DateTime anchor,
) async {
  final window = CalendarWindow(anchor: anchor, view: CalendarViewKind.month);
  await OccurrenceRepository(
    db,
  ).rebuildWindow(windowStartUtc: window.fromUtc, windowEndUtc: window.toUtc);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        calendarStateProvider.overrideWith(() => _FixedWindow(window)),
      ],
      child: const MaterialApp(home: Scaffold(body: MonthView())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'double-tapping a month day opens the 7-day timeline centered on it',
    (WidgetTester tester) async {
      final db = _db();
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      final target = day.add(const Duration(days: 2));
      await _pumpMonth(tester, db, today);

      final numberFinder = find.byKey(
        Key('month-day-number-${dateKey(target)}'),
      );
      await tester.tap(numberFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(numberFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MonthView)),
      );
      final window = container.read(calendarStateProvider);
      expect(window.view, CalendarViewKind.multiDay);
      expect(window.dayCount, 7);
      expect(window.anchor, target.subtract(const Duration(days: 3)));

      await _tearDown(tester, db);
    },
  );

  testWidgets('tapping a day number in the 7-day header invokes its callback', (
    WidgetTester tester,
  ) async {
    DateTime? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineDayHeader(
            anchor: DateTime(2027, 3, 1),
            dayCount: 7,
            gutterWidth: 48,
            onDayTap: (d) => tapped = d,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(tapped, DateTime(2027, 3, 1));

    final gestures = tester.widgetList<GestureDetector>(
      find.descendant(
        of: find.byType(TimelineDayHeader),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(gestures.any((g) => g.onTap != null), isTrue);
  });

  testWidgets('a 1-day header does not wire a day-tap handler', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineDayHeader(
            anchor: DateTime(2027, 3, 1),
            dayCount: 1,
            gutterWidth: 48,
            onDayTap: null,
          ),
        ),
      ),
    );
    await tester.pump();
    final gestures = tester.widgetList<GestureDetector>(
      find.descendant(
        of: find.byType(TimelineDayHeader),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(gestures.every((g) => g.onTap == null), isTrue);
  });
}
