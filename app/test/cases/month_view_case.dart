// Month view: event rows inside day cells, overflow count, day selection
// updating the agenda below, vertical scroll revealing it, and the empty
// state. Tapping a day selects it without leaving the month view.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/occurrence_repository.dart';
import 'package:ephemeron/features/calendar/application/calendar_providers.dart';
import 'package:ephemeron/features/calendar/application/calendar_state.dart';
import 'package:ephemeron/features/calendar/presentation/month_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seed(
  AppDatabase db,
  List<({String id, String title, DateTime day, int hour})> events,
) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await db
      .into(db.calendars)
      .insert(
        CalendarsCompanion.insert(
          id: 'cal1',
          name: 'c',
          createdAt: now,
          updatedAt: now,
        ),
      );
  for (final e in events) {
    final start = DateTime(e.day.year, e.day.month, e.day.day, e.hour).toUtc();
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: e.id,
            calendarId: 'cal1',
            title: Value(e.title),
            startUtc: Value(start.millisecondsSinceEpoch),
            endUtc: Value(
              start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}

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

Future<void> _revealAgenda(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  // Unmount and flush Drift's stream-cache timers before closing: closing
  // while a watched stream is still cached deadlocks on fake async.
  await tester.pumpWidget(Container());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('month cells show event titles for their day', (
    WidgetTester tester,
  ) async {
    final db = _db();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await _seed(db, [(id: 'e1', title: 'Standup', day: day, hour: 10)]);
    await _pumpMonth(tester, db, today);

    // Once in the grid cell, once in the selected-day agenda below.
    expect(find.text('Standup'), findsWidgets);
    await _tearDown(tester, db);
  });

  testWidgets('crowded days collapse into an overflow count', (
    WidgetTester tester,
  ) async {
    final db = _db();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await _seed(db, [
      for (var i = 0; i < 8; i++)
        (id: 'e$i', title: 'Event $i', day: day, hour: (8 + i) % 23),
    ]);
    await _pumpMonth(tester, db, today);

    expect(find.textContaining(RegExp(r'\+\d+ more')), findsOneWidget);
    await _tearDown(tester, db);
  });

  testWidgets('tapping a day selects it and updates the agenda', (
    WidgetTester tester,
  ) async {
    final db = _db();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    final other = day.add(const Duration(days: 2));
    await _seed(db, [
      (id: 'e1', title: 'Today Thing', day: day, hour: 10),
      (id: 'e2', title: 'Later Thing', day: other, hour: 11),
    ]);
    await _pumpMonth(tester, db, today);

    await tester.tap(find.byKey(Key('month-day-${dateKey(other)}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _revealAgenda(tester);

    expect(find.byKey(const ValueKey('month-agenda-e2')), findsOneWidget);
    expect(find.byKey(const ValueKey('month-agenda-e1')), findsNothing);
    await _tearDown(tester, db);
  });

  testWidgets('scrolling reveals the selected-day agenda below the grid', (
    WidgetTester tester,
  ) async {
    final db = _db();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await _seed(db, [(id: 'e1', title: 'Standup', day: day, hour: 10)]);
    await _pumpMonth(tester, db, today);

    await _revealAgenda(tester);

    expect(find.byKey(const Key('month-agenda-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('month-agenda-e1')), findsOneWidget);
    await _tearDown(tester, db);
  });

  testWidgets('days without events show the empty agenda state', (
    WidgetTester tester,
  ) async {
    final db = _db();
    await _seed(db, []);
    await _pumpMonth(tester, db, DateTime.now());

    await _revealAgenda(tester);

    expect(find.byKey(const Key('month-agenda-empty')), findsOneWidget);
    expect(find.text('Nothing scheduled'), findsOneWidget);
    await _tearDown(tester, db);
  });

  testWidgets('tapping an agenda event opens its details', (
    WidgetTester tester,
  ) async {
    final db = _db();
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await _seed(db, [(id: 'e1', title: 'Standup', day: day, hour: 10)]);
    await _pumpMonth(tester, db, today);
    await _revealAgenda(tester);

    await tester.tap(find.byKey(const ValueKey('month-agenda-e1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Edit'), findsOneWidget);
    await _tearDown(tester, db);
  });

  test('switching to the month view resets the anchor to today', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(calendarStateProvider.notifier);
    notifier.restore(CalendarViewKind.month, DateTime(2020, 1, 15));
    notifier.setView(CalendarViewKind.day);
    notifier.goTo(DateTime(2020, 5, 5));
    notifier.setView(CalendarViewKind.month);

    final window = container.read(calendarStateProvider);
    final now = DateTime.now();
    expect(window.view, CalendarViewKind.month);
    expect(window.anchor.year, now.year);
    expect(window.anchor.month, now.month);
    expect(window.anchor.day, now.day);
  });
}
